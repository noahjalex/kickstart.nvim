-- Run after a real startup in isolated XDG directories; see tests/migration-smoke.sh.
local function migration_smoke()
  vim.wait(50) -- Flush scheduled plugin setup (including Huez commands).
  local config = vim.fn.stdpath 'config'
  for _, kind in ipairs { 'config', 'data', 'state', 'cache' } do
    local xdg = assert(vim.env['XDG_' .. kind:upper() .. '_HOME'], 'Set isolated XDG directories')
    assert(vim.startswith(vim.fn.stdpath(kind), xdg), 'XDG isolation failed: ' .. kind)
  end
  for _, file in ipairs(vim.fn.globpath(config, '**/*.lua', false, true)) do
    assert(loadfile(file))
  end
  assert(not package.loaded.lazy, 'Lazy must not be loaded')
  assert(not vim.o.runtimepath:find('/lazy/', 1, true), 'Live Lazy store on runtimepath')
  assert(vim.o.relativenumber and vim.g.have_nerd_font)
  assert(vim.g.colors_name == 'tokyonight-night')

  for _, command in ipairs {
    'Git',
    'DiffviewOpen',
    'Oil',
    'DBUI',
    'Gen',
    'ZenMode',
    'LivePreview',
    'Huez',
    'HuezLive',
    'HuezFavorites',
    'HuezEnsured',
    'TransparentToggle',
    'HtmlB',
  } do
    assert(vim.fn.exists(':' .. command) == 2, 'Missing command: ' .. command)
  end
  for _, key in ipairs {
    '<F5>',
    '<F10>',
    '<F11>',
    '<F12>',
    '<leader>db',
    '<leader>dB',
    '<leader>dc',
    '<leader>dl',
    '<leader>dr',
    '<leader>dt',
    '<leader>du',
    '<leader>de',
    '<leader>dg',
    '<leader>dG',
    '<leader>gs',
    '<leader>gb',
    '<leader>gl',
    '<leader>gp',
    '<leader>gd',
    '<leader>gD',
    '<leader>gh',
    '<leader>pv',
    '<leader>cs',
    '<leader>cl',
    '<leader>cf',
    '<leader>ce',
    '<leader>tt',
    '<leader>tz',
    '<leader>at',
    '<leader>ag',
    '<leader>aa',
    '<leader>ah',
    '<leader>sF',
    '<leader>ko',
    '<leader>kb',
    '<leader>ks',
  } do
    assert(vim.fn.maparg(key, 'n') ~= '', 'Missing keymap: ' .. key)
  end
  require('telescope').load_extension 'fzf'
  require('telescope').load_extension 'ui-select'
  assert(require 'luasnip.util.jsregexp', 'LuaSnip regex build missing')
  require 'lazydev.integrations.blink'
  require 'vim_dadbod_completion.blink'
  local completion = require 'blink.cmp.config'
  assert(completion.snippets.preset == 'luasnip')
  assert(vim.tbl_contains(completion.sources.default, 'buffer'))
  assert(completion.sources.per_filetype.sql[2] == 'dadbod')
  assert(vim.lsp.config.lua_ls.settings.Lua.completion.callSnippet == 'Replace')
  assert(vim.lsp.config.kotlin_lsp.cmd[1] == 'intellij-server')
  assert(vim.lsp.is_enabled 'templ' and vim.lsp.is_enabled 'kotlin_lsp')
  assert(not vim.lsp.is_enabled 'jdtls' and not vim.lsp.is_enabled 'kotlin_language_server')
  assert(vim.lsp.config.lua_ls.capabilities.textDocument.completion.completionItem.snippetSupport)
  assert(require('dap').adapters.codelldb and require('dap').configurations.zig[1])
  assert(require('dap').configurations.go and require 'dapui')
  local huez_backend = require 'huez-manager.api.selected'
  huez_backend.lazy_flush { 'tokyonight', 'rose-pine' }
  -- Exercise new-theme installation as well as reuse of canonical package names.
  huez_backend.lazy_flush { 'nightfox' }
  vim.cmd.colorscheme 'nightfox'
  assert(vim.g.colors_name == 'nightfox')
  vim.cmd.colorscheme 'tokyonight-night'
  assert(not package.loaded.lazy)

  assert(
    vim.wait(180000, function()
      local registry = require 'mason-registry'
      for _, tool in ipairs { 'stylua', 'lua-language-server', 'kotlin-lsp', 'templ', 'tree-sitter-cli' } do
        if not registry.has_package(tool) or not registry.get_package(tool):is_installed() then return false end
      end
      local installed = require('nvim-treesitter').get_installed 'parsers'
      for _, parser in ipairs {
        'bash',
        'c',
        'diff',
        'go',
        'gomod',
        'gosum',
        'html',
        'java',
        'kotlin',
        'templ',
        'json',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'query',
        'rust',
        'vim',
        'vimdoc',
      } do
        if not vim.tbl_contains(installed, parser) then return false end
      end
      return true
    end, 100),
    'Mason tools or Treesitter parsers did not install'
  )

  local directory = vim.fn.stdpath 'state' .. '/migration-smoke'
  vim.fn.mkdir(directory, 'p')
  vim.fn.writefile({ '{}' }, directory .. '/.luarc.json')
  local source = directory .. '/sample.lua'
  vim.fn.writefile({ 'local value={1,2}', 'return value' }, source)
  vim.cmd.edit(source)
  local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.cmd.write()
  vim.wait(100)
  assert(vim.deep_equal(before, vim.fn.readfile(source)), 'Saving must not format')
  local conform = require 'conform'
  local format, called = conform.format, nil
  conform.format = function(opts) called = opts end
  vim.fn.maparg('<leader>f', 'n', false, true).callback()
  assert(called.async and not called.range and called.lsp_format == 'fallback')
  vim.api.nvim_buf_set_mark(0, '<', 2, 0, {})
  vim.api.nvim_buf_set_mark(0, '>', 1, 0, {})
  vim.fn.maparg('<leader>f', 'x', false, true).callback()
  assert(vim.deep_equal(called.range, { start = { 1, 0 }, ['end'] = { 2, #before[2] } }))
  conform.format = format
  conform.format { async = false, timeout_ms = 10000, lsp_format = 'never' }
  assert(not vim.deep_equal(before, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Manual Stylua formatting failed')
  local selection = { 'local first={1,2}', '', 'local second={3,4}', 'return first,second' }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, selection)
  conform.format { async = false, timeout_ms = 10000, lsp_format = 'never', range = { start = { 3, 0 }, ['end'] = { 3, #selection[3] } } }
  local selected_result = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(
    selected_result[1] == selection[1] and selected_result[3] ~= selection[3] and selected_result[4] == selection[4],
    'Selection formatting changed unselected code'
  )
  for _, event in ipairs { 'BufWritePre', 'BufWritePost' } do
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds { event = event }) do
      assert(not (autocmd.desc or ''):lower():find 'format', 'Unexpected format-on-save hook')
    end
  end

  local client
  assert(
    vim.wait(45000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = 'lua_ls' })[1]
      return client and client.initialized
    end, 100),
    'Lua LSP did not attach'
  )
  for _, key in ipairs { 'rn', 'ca', 'gr', 'gI', 'gd', 'gD', 'gO', 'gW', 'gt', 'K', 'lK', 'grn', 'gra', 'grr', 'gri', 'grd', 'grt' } do
    assert(vim.fn.maparg(key, 'n') ~= '', 'Missing attached LSP keymap: ' .. key)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local value = string.' })
  assert(
    vim.wait(15000, function()
      local reply = client:request_sync('textDocument/completion', {
        textDocument = vim.lsp.util.make_text_document_params(),
        position = { line = 0, character = 21 },
      }, 3000, 0)
      return reply and reply.result and #(reply.result.items or reply.result) > 0
    end, 500),
    'Real Lua LSP completion failed'
  )

  -- Exercise the Java FileType hook without launching/importing a real project.
  vim.fn.writefile({}, directory .. '/.jdtls-root')
  local jdtls, java_config = require 'jdtls', nil
  local start_or_attach = jdtls.start_or_attach
  jdtls.start_or_attach = function(opts) java_config = opts end
  vim.cmd 'enew!'
  vim.api.nvim_buf_set_name(0, directory .. '/Main.java')
  vim.bo.filetype = 'java'
  jdtls.start_or_attach = start_or_attach
  assert(java_config and vim.uv.fs_realpath(java_config.root_dir) == vim.uv.fs_realpath(directory), vim.inspect(java_config))
  assert(java_config.settings.java.autobuild.enabled == false)
  assert(vim.startswith(java_config.cmd[3], vim.fn.stdpath 'data'))

  -- Exercise the real HTTP route wrapper, including traversal and symlink escape.
  local server = require('livepreview.server').Server:new(directory)
  local preview_config = require('livepreview.config').config
  assert(preview_config.address == '127.0.0.1' and preview_config.dynamic_root == false)
  vim.fn.writefile({ '# Markdown' }, directory .. '/inside.md')
  local outside = directory .. '-outside.md'
  vim.fn.writefile({ 'private' }, outside)
  vim.uv.fs_unlink(directory .. '/escape.md')
  assert(vim.uv.fs_symlink(outside, directory .. '/escape.md'))
  assert(server:routes '/inside.md' == vim.uv.fs_realpath(directory .. '/inside.md'))
  assert(server:routes '/escape.md' == '')
  assert(server:routes '../migration-smoke-outside.md' == '')
  assert(server:routes(outside) == '')
  assert(server:routes '/missing.md' == '')
  server:start(preview_config.address, 0, {})
  local address = server.server:getsockname()
  assert(address.ip == '127.0.0.1', 'Preview must bind only to localhost')
  for path, expected in pairs { ['/inside.md'] = '200', ['/escape.md'] = '404', ['/../migration-smoke-outside.md'] = '404' } do
    local response = vim
      .system(
        { 'curl', '--path-as-is', '--silent', '--output', '/dev/null', '--write-out', '%{http_code}', 'http://127.0.0.1:' .. address.port .. path },
        { text = true }
      )
      :wait(5000)
    assert(response.code == 0 and response.stdout == expected, 'HTTP preview confinement failed: ' .. path .. ' ' .. vim.inspect(response))
  end
  server:stop()
  vim.cmd 'enew!'
  vim.api.nvim_buf_set_name(0, directory .. '/inside.md')
  vim.bo.filetype = 'markdown'
  assert(vim.fn.maparg('<leader>rm', 'n') ~= '')
  local root = require('custom.markdown-preview').markdown_preview_root(directory .. '/inside.md', '[local](inside.md)')
  assert(root == directory)
  assert(#(_G.migration_errors or {}) == 0, table.concat(_G.migration_errors or {}, '\n'))
  print 'PASS: Lua syntax, native builds, plugins, keymaps, LSP/completion, manual formatting, Java/DAP configuration, Huez backend, Markdown route confinement'
end

local ok, err = xpcall(migration_smoke, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd 'cquit 1'
end
vim.cmd 'qa!'
