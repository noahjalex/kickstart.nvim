vim.pack.add {
  -- The work-theme adapter requires Base16 even when no Base16 scheme is selected.
  { src = 'https://github.com/RRethy/base16-nvim', name = 'base16' },
  'https://github.com/xiyaowong/transparent.nvim',
}

vim.keymap.set('n', '<leader>cs', '<cmd>Telescope colorscheme<cr>', { desc = '[C]olorscheme [S]elect' })

require('transparent').setup { extra_groups = { 'NormalFloat', 'FloatBorder', 'FoldColumn', 'WinSeparator' } }
vim.keymap.set('n', '<leader>tt', '<cmd>TransparentToggle<cr>', { desc = '[T]oggle [T]ransparency' })
