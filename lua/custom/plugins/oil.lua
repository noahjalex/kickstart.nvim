return {
  'stevearc/oil.nvim',
  lazy = false,
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  keys = {
    { '<leader>pv', '<cmd>Oil<cr>', desc = 'Open parent directory' },
  },
  opts = {
    confirmation = {
      border = 'rounded',
    },
    view_options = {
      show_hidden = true,
    },
  },
}
