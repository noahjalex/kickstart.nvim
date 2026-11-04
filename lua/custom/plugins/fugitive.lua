vim.pack.add {
  'https://github.com/tpope/vim-fugitive',
  'https://github.com/sindrets/diffview.nvim',
}
require('diffview').setup {}
vim.keymap.set('n', '<leader>gs', '<cmd>Git<cr>', { desc = '[G]it [S]tatus' })
vim.keymap.set('n', '<leader>gb', '<cmd>Git blame<cr>', { desc = '[G]it [B]lame' })
vim.keymap.set('n', '<leader>gl', '<cmd>Git log<cr>', { desc = '[G]it [L]og' })
vim.keymap.set('n', '<leader>gp', '<cmd>Git push<cr>', { desc = '[G]it [P]ush' })
vim.keymap.set('n', '<leader>gd', '<cmd>DiffviewOpen<cr>', { desc = '[G]it [D]iff working tree' })
vim.keymap.set('n', '<leader>gD', ':DiffviewOpen ', { desc = '[G]it [D]iff refs' })
vim.keymap.set('n', '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', { desc = '[G]it file [H]istory' })
