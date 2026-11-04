vim.pack.add { 'https://github.com/stevearc/oil.nvim' }
require('oil').setup {
  confirmation = { border = 'rounded' },
  view_options = { show_hidden = true },
}
vim.keymap.set('n', '<leader>pv', '<cmd>Oil<cr>', { desc = 'Open parent directory' })
