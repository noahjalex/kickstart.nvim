-- Run with the real init.lua and the built native app, not a fake socket or renderer.
local preview = require 'custom.markdown-preview'
local directory = assert(vim.env.MARKDOWN_PREVIEW_TEST_DIRECTORY)
local replies, warnings = {}, {}
local notify = vim.notify
vim.notify = function(message, level, options)
  warnings[#warnings + 1] = tostring(message)
  notify(message, level, options)
end
vim.api.nvim_create_autocmd('User', {
  pattern = 'MarkdownPreviewUpdated',
  callback = function(event) replies[#replies + 1] = event.data end,
})
vim.g.markdown_preview_opacity = 0.65
vim.g.markdown_preview_config = directory .. '/preview-style.json'
vim.fn.writefile({ '{"body":{"family":"Menlo","size":16},"articleWidth":720,"cornerRadius":12}' }, vim.g.markdown_preview_config)
local function wait_for(predicate, message) assert(vim.wait(10000, predicate, 20), message) end
local function render_mapping() vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(' rm', true, false, true), 'xt', false) end
local function open_markdown(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  assert(vim.bo.filetype == 'markdown')
  assert(vim.fn.maparg(' rm', 'n', false, true).buffer == 1, 'real buffer-local mapping missing')
end
local function latest() return replies[#replies] end
local function run()
  local highlighted = preview.markdown_preview_code_highlights('```lua\nlocal x = "日本語"\n```\n\n```go\npackage main\n```\n\n```not_a_language\nuntouched\n```')
  assert(#highlighted == 3 and #highlighted[1].spans > 0 and #highlighted[2].spans > 0, 'installed Lua/Go parsers did not highlight')
  assert(#highlighted[3].spans == 0, 'unknown language must stay plain')
  assert(highlighted[1].code == 'local x = "日本語"\n')
  local nested = preview.markdown_preview_code_highlights('- list\n\n  ```lua\n  local x = 1\n  print(x)\n  ```\n\n> ```lua\n> local y = 2\n> ```')
  assert(nested[1].code == 'local x = 1\nprint(x)\n', 'list prefixes leaked into code')
  assert(nested[2].code == 'local y = 2\n', 'quote prefixes leaked into code')
  local indented = preview.markdown_preview_code_highlights('  ```lua\n  local x = 1\n    print(x)\n  ```')
  assert(indented[1].code == 'local x = 1\n  print(x)\n', 'fence indentation leaked into code')
  local sockets_before = vim.fn.glob '/tmp/nvim-markdown-*'
  vim.cmd.enew()
  vim.bo.filetype = 'markdown'
  render_mapping()
  assert(warnings[#warnings]:find 'save this file', 'unnamed file warning missing')
  open_markdown(directory .. '/does-not-exist.md')
  render_mapping()
  assert(warnings[#warnings]:find 'save this file', 'nonexistent file warning missing')
  assert(#replies == 0)
  assert(vim.fn.glob '/tmp/nvim-markdown-*' == sockets_before, 'invalid file launched the app')
  open_markdown(directory .. '/escape.md')
  render_mapping()
  assert(warnings[#warnings]:find 'source resolves outside the inferred root', 'source symlink escape was not rejected')
  assert(vim.fn.glob '/tmp/nvim-markdown-*' == sockets_before, 'symlink escape launched the app')

  local first = directory .. '/first.md'
  open_markdown(first)
  local cwd = vim.fn.getcwd()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Unsaved launch', '', '**Native** preview 日本語', '', '```lua', 'local value = "日本語"', '```' })
  render_mapping()
  wait_for(function() return latest() and latest().rendered:find 'Unsaved launch' end, 'initial unsaved snapshot not displayed')
  assert(latest().syntaxSpans > 0, 'Tree-sitter captures did not reach the native renderer')
  assert(latest().bodyFont == 'Menlo' and latest().readingWidth == 720, 'configured font/reading width did not reach the app')
  local window, pid = latest().window, latest().pid
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local dark = vim.o.background == 'dark'
  local foreground = normal.fg or (dark and 0xc0caf5 or 0x24283b)
  local background = normal.bg or (dark and 0x1a1b26 or 0xffffff)
  assert(latest().theme.foreground == string.format('#%06x', foreground), 'Neovim foreground not inherited')
  assert(latest().theme.background == string.format('#%06x', background), 'Neovim background not inherited')
  assert(latest().darkAppearance == (vim.o.background == 'dark'), 'native appearance does not match Neovim')
  for index, shift in ipairs { 16, 8, 0 } do
    local expected = math.floor(background / 2 ^ shift) % 256 / 255
    assert(math.abs(latest().backgroundRGB[index] - expected) < 0.001, 'window background does not match Neovim')
  end
  local launch_theme = vim.deepcopy(latest().theme)
  vim.api.nvim_set_hl(0, 'Normal', { fg = '#112233', bg = '#fafafa' })
  assert(latest().windows == 1)
  assert(math.abs(latest().backgroundAlpha - 0.65) < 0.01 and latest().windowAlpha == 1)
  assert(vim.fn.getcwd() == cwd, 'preview changed editor working directory')
  assert(not require('livepreview').is_running(), 'mapping started LivePreview')
  local first_buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Edited without saving', '', '[outside](../outside.md)' })
  wait_for(function() return latest().rendered:find 'Edited without saving' end, 'live edit not received')
  assert(latest().window == window and latest().pid == pid)
  assert(vim.deep_equal(latest().theme, launch_theme), 'editing changed the launch theme')
  vim.api.nvim_set_hl(0, 'Normal', normal)
  assert(latest().root == directory, 'editing widened the security boundary')
  assert(vim.fn.readfile(first)[1] == '# Saved first', 'preview wrote document edits')

  vim.cmd 'set hidden'
  open_markdown(directory .. '/second.md')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Second unsaved buffer' })
  render_mapping()
  wait_for(function() return latest().rendered:find 'Second unsaved buffer' end, 'buffer switch not displayed')
  assert(latest().window == window and latest().pid == pid and latest().windows == 1, 'buffer switch created another window/process')
  vim.api.nvim_set_current_buf(first_buffer)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Returning unsaved buffer' })
  render_mapping()
  wait_for(function() return latest().rendered:find 'Returning unsaved buffer' end, 'buffer reuse lost unsaved contents')
  -- A lost app is not restarted by editing, and the editor's unsaved text survives.
  assert(vim.uv.kill(pid, 15))
  wait_for(function() return vim.uv.kill(pid, 0) == nil end, 'closed app was not reaped')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Still editing after app closed' })
  vim.wait(200, function() return false end)
  assert(vim.fn.glob '/tmp/nvim-markdown-*' == sockets_before, 'editing reopened a closed app')
  render_mapping()
  wait_for(function() return latest().pid ~= pid and latest().rendered:find 'Still editing after app closed' end, 'explicit reopening lost unsaved text')
  pid, window = latest().pid, latest().window
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Live edit after reopening' })
  wait_for(function() return latest().rendered:find 'Live edit after reopening' end, 'reopened preview did not reattach edits')
  vim.fn.writefile({ vim.json.encode { pid = pid, window = window, replies = #replies, status = 'passed' } }, directory .. '/neovim-result.json')
end
local ok, error = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(error .. '\n')
  vim.cmd 'cquit 1'
else
  print 'PASS: real Neovim mapping, saved-path validation, unsaved snapshots, live edits, root freeze, buffer/window reuse, opacity'
  vim.cmd 'qa!'
end
