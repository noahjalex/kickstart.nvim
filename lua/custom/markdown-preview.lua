local M = {}

--- Find the common directory of a Markdown file and its local link destinations.
function M.markdown_preview_root(filename, text)
  local directory = vim.fs.dirname(vim.fs.normalize(filename))
  local root = directory
  local parser = vim.treesitter.get_string_parser(text, 'markdown')
  parser:parse(true)
  parser:for_each_tree(function(tree, language)
    if language:lang() ~= 'markdown' and language:lang() ~= 'markdown_inline' then
      return
    end
    local query = vim.treesitter.query.parse(language:lang(), '(link_destination) @path')
    for _, node in query:iter_captures(tree:root(), text) do
      local path = vim.treesitter.get_node_text(node, text):gsub('^<(.*)>$', '%1')
      if not path:match '^[%a][%w+.-]*:' and not vim.startswith(path, '//') then
        path = path:gsub('[?#].*$', '')
        path = vim.uri_decode(path:gsub('\\([%p])', '%1'))
        if path ~= '' then
          local target = vim.fs.normalize(vim.startswith(path, '/') and path or vim.fs.joinpath(directory, path))
          while root ~= '/' and target ~= root and not vim.startswith(target, root .. '/') do
            root = vim.fs.dirname(root)
          end
        end
      end
    end
  end)
  return root
end

--- Start the browser preview with a window-local root inferred from the current buffer.
function M.start_markdown_preview()
  local filename = vim.api.nvim_buf_get_name(0)
  if filename == '' or vim.fn.filereadable(filename) == 0 then
    vim.notify('Markdown preview: save this file before opening the browser', vim.log.levels.WARN)
    return
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  vim.cmd.lcd(M.markdown_preview_root(filename, text))
  vim.cmd 'LivePreview start'
end

return M
