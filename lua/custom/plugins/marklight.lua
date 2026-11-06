local checkout = vim.fn.expand '~/Development/noahjalex/marklight'
if vim.fn.isdirectory(checkout .. '/neovim') == 0 then return end
vim.opt.rtp:append(checkout .. '/neovim')
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(event)
    vim.keymap.set('n', '<leader>rm', '<cmd>Marklight<cr>', { buffer = event.buf, desc = 'Open Marklight' })
  end,
})
