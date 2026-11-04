local filename = vim.fs.joinpath(vim.fn.stdpath 'config', 'snippets', 'boilerplate.html')

if vim.fn.filereadable(filename) == 1 then
  vim.api.nvim_create_user_command('HtmlB', function() vim.cmd('read ' .. vim.fn.fnameescape(filename)) end, {})
else
  -- optional: warn but keep startup quiet
  vim.notify('HTML boilerplate not found: ' .. filename, vim.log.levels.WARN)
end
