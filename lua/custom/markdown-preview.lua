local M = {}
local uv = vim.uv
local session
local repository = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(assert(uv.fs_realpath(debug.getinfo(1, 'S').source:sub(2))))))

--- Find the common directory of a Markdown file and its local link destinations.
function M.markdown_preview_root(filename, text)
  local directory = vim.fs.dirname(vim.fs.normalize(filename))
  local root = directory
  local parser = vim.treesitter.get_string_parser(text, 'markdown')
  parser:parse(true)
  parser:for_each_tree(function(tree, language)
    if language:lang() ~= 'markdown' and language:lang() ~= 'markdown_inline' then return end
    local query = vim.treesitter.query.parse(language:lang(), '(link_destination) @path')
    for _, node in query:iter_captures(tree:root(), text) do
      local path = vim.treesitter.get_node_text(node, text):gsub('^<(.*)>$', '%1')
      if not path:match '^[%a][%w+.-]*:' and not vim.startswith(path, '//') then
        path = path:gsub('[?#].*$', '')
        path = vim.uri_decode(path:gsub('\\([%p])', '%1'))
        if path ~= '' then
          local target = vim.fs.normalize(vim.startswith(path, '/') and path or vim.fs.joinpath(directory, path))
          while root ~= '/' and target ~= root and not vim.startswith(target, root .. '/') do
            root = vim.fs.dirname(root)
          end
        end
      end
    end
  end)
  return root
end

local function warn(message) vim.notify('Markdown preview: ' .. message, vim.log.levels.WARN) end

local function close_handle(handle)
  if handle and not handle:is_closing() then handle:close() end
end

local function stop_preview(state)
  if session ~= state then return end
  session = nil
  close_handle(state.client)
  close_handle(state.server)
  close_handle(state.timer)
  uv.fs_unlink(state.socket)
  uv.fs_rmdir(state.directory)
  -- Closing the socket makes the native app exit; no polling process or helper to reap.
end

-- Capture resolved highlight colors once per native app launch, including linked groups.
local function markdown_preview_theme()
  local dark = vim.o.background == 'dark'
  local function color(groups, field, fallback)
    for _, group in ipairs(groups) do
      local hl = vim.api.nvim_get_hl(0, { name = group, link = false, create = false })
      local value = hl[hl.reverse and (field == 'fg' and 'bg' or 'fg') or field]
      if value then return string.format('#%06x', value) end
    end
    return fallback
  end
  local foreground = color({ 'Normal' }, 'fg', dark and '#c0caf5' or '#24283b')
  local background = color({ 'Normal' }, 'bg', dark and '#1a1b26' or '#ffffff')
  local colors = {
    foreground = foreground,
    background = background,
    link = color({ '@markup.link.url', 'Underlined', 'Identifier' }, 'fg', foreground),
    code = color({ '@markup.raw', 'String' }, 'fg', foreground),
    codeBackground = color({ 'NormalFloat', 'CursorLine' }, 'bg', background),
    quote = color({ '@markup.quote', 'Comment' }, 'fg', foreground),
    border = color({ 'FloatBorder', 'Comment' }, 'fg', foreground),
    selection = color({ 'Visual' }, 'bg', background),
  }
  for level = 1, 6 do
    colors['heading' .. level] = color({ '@markup.heading.' .. level, 'Title' }, 'fg', foreground)
  end
  return { dark = dark, colors = colors }
end

local function send_snapshot(state, buffer, activate)
  if session ~= state or not state.client or not vim.api.nvim_buf_is_valid(buffer) then return end
  local document = state.documents[buffer]
  if not document then return end
  if state.writing then
    state.pending[buffer] = activate or state.pending[buffer] or false
    return
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
  local frame = vim.json.encode {
    source = document.source,
    root = document.root,
    text = text,
    opacity = math.max(0, math.min(1, tonumber(vim.g.markdown_preview_opacity) or 0.96)),
    activate = activate,
    theme = state.theme,
  } .. '\n'
  if #frame > 16 * 1024 * 1024 then
    warn 'buffer exceeds the 16 MiB IPC limit'
    return
  end
  state.writing = true
  state.client:write(
    frame,
    vim.schedule_wrap(function(err)
      state.writing = false
      if err then stop_preview(state) end
      if session ~= state then return end
      local next_buffer, next_activate = next(state.pending)
      if next_buffer then
        state.pending[next_buffer] = nil
        send_snapshot(state, next_buffer, next_activate and next_buffer == state.selected)
      end
    end)
  )
end

local function attach_buffer(state, buffer)
  local function changed()
    if session ~= state then return true end
    if not state.client then return end -- The first connected snapshot reads the latest buffer.
    state.dirty[buffer] = true
    -- ponytail: full snapshots after debounce; add incremental rendering only if large documents measurably lag.
    state.timer:start(
      80,
      0,
      vim.schedule_wrap(function()
        for changed_buffer in pairs(state.dirty) do
          send_snapshot(state, changed_buffer, false)
        end
        state.dirty = {}
      end)
    )
  end
  vim.api.nvim_buf_attach(buffer, false, {
    on_lines = changed,
    on_reload = changed,
    on_detach = function()
      state.documents[buffer] = nil
      state.pending[buffer] = nil
      state.dirty[buffer] = nil
    end,
  })
end

--- Launch or reuse the native preview; only saved paths are accepted, but contents come from the buffer.
function M.start_markdown_preview()
  local buffer = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(buffer)
  if filename == '' or vim.fn.filereadable(filename) == 0 then
    warn 'save this file before opening the native preview'
    return
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
  if #vim.json.encode(text) > 16 * 1024 * 1024 - 4096 then
    warn 'buffer exceeds the 16 MiB IPC limit'
    return
  end
  local ok, root = pcall(M.markdown_preview_root, filename, text)
  if not ok then
    warn('cannot infer root: ' .. root)
    return
  end
  -- Do not widen the inferred root to accommodate a symlink escaping it.
  local realroot, realfile = uv.fs_realpath(root), uv.fs_realpath(filename)
  if not realroot or not realfile or (realfile ~= realroot and not vim.startswith(realfile, realroot:gsub('/$', '') .. '/')) then
    warn 'source resolves outside the inferred root'
    return
  end
  if not session then
    local executable = vim.g.markdown_preview_executable or (repository .. '/native/markdown-preview/Markdown Preview.app/Contents/MacOS/MarkdownPreview')
    if vim.fn.executable(executable) ~= 1 then
      warn 'native app is not installed; run native/markdown-preview/build.sh'
      return
    end
    local directory, err = uv.fs_mkdtemp '/tmp/nvim-markdown-XXXXXX'
    if not directory then
      warn('cannot create private socket directory: ' .. tostring(err))
      return
    end
    uv.fs_chmod(directory, 448) -- 0700; the socket is never exposed through HTTP.
    local state = {
      directory = directory,
      socket = directory .. '/editor.sock',
      server = uv.new_pipe(false),
      timer = uv.new_timer(),
      documents = {},
      dirty = {},
      pending = {},
      theme = markdown_preview_theme(),
    }
    session = state
    local bound, bind_error = state.server:bind(state.socket)
    if not bound then
      warn('cannot bind socket: ' .. tostring(bind_error))
      stop_preview(state)
      return
    end
    state.server:listen(
      1,
      vim.schedule_wrap(function(accept_error)
        if session ~= state or accept_error or state.client then return end
        local client = uv.new_pipe(false)
        state.server:accept(client)
        state.client = client
        close_handle(state.server) -- Exactly one native app per editor session.
        local pending = ''
        client:read_start(vim.schedule_wrap(function(read_error, data)
          if read_error or not data then
            stop_preview(state)
            return
          end
          pending = pending .. data
          if #pending > 32 * 1024 * 1024 then
            stop_preview(state)
            return
          end
          while pending:find('\n', 1, true) do
            local newline = pending:find('\n', 1, true)
            local decoded, reply = pcall(vim.json.decode, pending:sub(1, newline - 1))
            pending = pending:sub(newline + 1)
            if decoded then
              if reply.error then
                warn(reply.error)
              else
                vim.api.nvim_exec_autocmds('User', { pattern = 'MarkdownPreviewUpdated', data = reply })
              end
            end
          end
        end))
        send_snapshot(state, state.selected, true)
      end)
    )
    state.job = vim.fn.jobstart({ executable, '--socket', state.socket }, {
      on_exit = function(_, code)
        if session == state then
          stop_preview(state)
          if code ~= 0 then warn('native app exited with code ' .. code) end
        end
      end,
    })
    if state.job <= 0 then
      warn 'could not launch native app'
      stop_preview(state)
      return
    end
    -- A failed launch or broken connection must not leave a listening socket indefinitely.
    state.timer:start(
      10000,
      0,
      vim.schedule_wrap(function()
        if session == state and not state.client then
          stop_preview(state)
          pcall(vim.fn.jobstop, state.job)
          warn 'native app did not connect within 10 seconds'
        end
      end)
    )
  end
  local state = session
  local attached = state.documents[buffer] ~= nil
  state.documents[buffer] = { source = realfile, root = realroot }
  state.selected = buffer
  if not attached then attach_buffer(state, buffer) end
  send_snapshot(state, buffer, true)
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('native-markdown-preview', { clear = true }),
  callback = function()
    if session then stop_preview(session) end
  end,
})

return M
