-- :PasteImage / <leader>ii: save the clipboard image next to the current file as
-- <name>-NN.png (next free number) and insert ![img](./<name>-NN.png) at the cursor. macOS only.
local function paste_image()
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then return vim.notify('PasteImage: save this buffer to a file first', vim.log.levels.ERROR) end
  local dir, name = vim.fn.fnamemodify(file, ':p:h'), vim.fn.fnamemodify(file, ':t:r')

  -- Next number = highest existing <name>-NN.* + 1, so nothing gets overwritten.
  local n = 0
  for entry in vim.fs.dir(dir) do
    local num = entry:match('^' .. vim.pesc(name) .. '%-(%d+)%.%w+$')
    if num then n = math.max(n, tonumber(num)) end
  end
  local image = string.format('%s-%02d.png', name, n + 1)
  local path = dir .. '/' .. image

  -- Clipboard images on macOS (screenshots, copied images) are available as PNG.
  local result = vim.system({ 'osascript',
    '-e', 'set png to (the clipboard as «class PNGf»)',
    '-e', 'set f to open for access (POSIX file "' .. path .. '") with write permission',
    '-e', 'write png to f',
    '-e', 'close access f',
  }):wait()
  if result.code ~= 0 then
    os.remove(path)
    return vim.notify('PasteImage: no image on the clipboard (copy one first, e.g. ⌘⌃⇧4)', vim.log.levels.ERROR)
  end

  vim.api.nvim_put({ '![img](./' .. image .. ')' }, 'c', true, true)
  vim.notify('PasteImage: saved ' .. image)
end

vim.api.nvim_create_user_command('PasteImage', paste_image, { desc = 'Paste clipboard image as a Markdown link' })
vim.keymap.set('n', '<leader>ii', paste_image, { desc = '[I]mage [I]nsert from clipboard' })
