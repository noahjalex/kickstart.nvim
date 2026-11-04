vim.pack.add {
  'https://github.com/folke/zen-mode.nvim',
  'https://github.com/mistweaverco/kulala.nvim',
  'https://github.com/ibhagwan/fzf-lua',
  'https://github.com/David-Kunz/gen.nvim',
  'https://github.com/brianhuster/live-preview.nvim',
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
}

require('zen-mode').setup {}
vim.keymap.set('n', '<leader>tz', '<cmd>ZenMode<CR>', { desc = '[T]oggle [Z]en mode' })
require('kulala').setup { global_keymaps = true, global_keymaps_prefix = '<leader>k' }
require('fzf-lua').setup {
  winopts = {
    width = 0.98,
    height = 0.95,
    preview = { layout = 'horizontal', horizontal = 'right:35%' },
  },
}

-- Open-source, local AI syntax help/completions via Ollama.
local gen = require 'gen'
gen.setup {
  model = 'qwen3-coder:latest',
  display_mode = 'float',
  win_config = {
    relative = 'editor',
    width = math.floor(vim.o.columns * 0.9),
    height = math.floor(vim.o.lines * 0.75),
    row = math.floor(vim.o.lines * 0.1),
    col = math.floor(vim.o.columns * 0.05),
    border = 'rounded',
  },
  show_prompt = false,
  show_model = true,
}
gen.prompts.Complete_Code = {
  prompt = 'Complete the following $filetype code. Only output the completed code in format ```$filetype\n...\n```:\n```$filetype\n$text\n```',
  replace = true,
  extract = '```$filetype\n(.-)```',
}
gen.prompts.SyntaxHelp = {
  prompt = 'Explain the syntax or idiom in this $filetype code briefly. Include the corrected form if something is wrong:\n```$filetype\n$text\n```',
}
vim.keymap.set('n', '<leader>at', '<cmd>Gen Chat<CR>', { desc = 'AI chat' })
vim.keymap.set('n', '<leader>ag', '<cmd>Gen Generate<CR>', { desc = 'AI generate' })
vim.keymap.set('v', '<leader>ag', ':Gen Generate<CR>', { desc = 'AI generate' })
vim.keymap.set('n', '<leader>aa', '<cmd>Gen Ask<CR>', { desc = 'AI ask about buffer' })
vim.keymap.set('v', '<leader>aa', ':Gen Ask<CR>', { desc = 'AI ask about selection' })
vim.keymap.set('v', '<leader>ar', ':Gen Change<CR>', { desc = 'AI rewrite selection' })
vim.keymap.set('n', '<leader>ah', '<cmd>Gen SyntaxHelp<CR>', { desc = 'AI syntax help' })
vim.keymap.set('v', '<leader>ah', ':Gen SyntaxHelp<CR>', { desc = 'AI syntax help' })
vim.keymap.set('v', '<leader>ac', ':Gen Complete_Code<CR>', { desc = 'AI complete selected code' })

require('render-markdown').setup {
  pipe_table = { cell = 'trimmed', min_width = 3, preset = 'round', style = 'full' },
}
require('livepreview.config').set { address = '127.0.0.1', dynamic_root = false, browser = 'open -a Safari' }

-- Confine directory hosting to the webroot, including symlink targets.
local server = require('livepreview.server').Server
local routes = server.routes
local plugin_root = require('livepreview.utils').get_plugin_path()
function server:routes(path)
  local plugin_asset = vim.startswith(path, '/live-preview.nvim/')
  local root = vim.uv.fs_realpath(plugin_asset and plugin_root or self.webroot)
  local target = vim.uv.fs_realpath(routes(self, path))
  -- Absolute filesystem links also work, but only inside the chosen root.
  if not target and not plugin_asset then target = vim.uv.fs_realpath(path) end
  if root and target and vim.startswith(target, root:gsub('/$', '') .. '/') then return target end
  return '' -- The HTTP handler returns 404 for missing or out-of-root files.
end
