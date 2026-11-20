-- Inline Markdown images (Ghostty/Kitty graphics, works in tmux with allow-passthrough).
-- Non-PNG needs ImageMagick. Check with :checkhealth snacks
vim.pack.add { 'https://github.com/folke/snacks.nvim' }
require('snacks').setup {
  image = { enabled = true },
}

-- Image preview: open the image under the cursor in Preview (zoom/pan there).
vim.keymap.set('n', '<leader>ip', function()
  Snacks.image.doc.at_cursor(function(src)
    if src then vim.ui.open(src) else vim.notify('No image under cursor', vim.log.levels.WARN) end
  end)
end, { desc = '[I]mage [P]review in Preview.app' })

-- Escape hatch: stop all image rendering for this Neovim session (restart to turn back on).
vim.api.nvim_create_user_command('ImagesOff', function()
  Snacks.image.config.enabled = false
  pcall(vim.api.nvim_del_augroup_by_name, 'snacks.image')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    pcall(vim.api.nvim_del_augroup_by_name, 'snacks.image.inline.' .. buf)
    pcall(vim.api.nvim_del_augroup_by_name, 'snacks.image.doc.' .. buf)
  end
  Snacks.image.placement.clean()
  vim.notify 'Images off until restart'
end, { desc = 'Turn off snacks image rendering for this session' })
