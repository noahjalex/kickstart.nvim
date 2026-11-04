vim.pack.add {
  { src = 'https://github.com/vague2k/huez.nvim', version = 'stable' },
  'https://github.com/xiyaowong/transparent.nvim',
}

-- Huez stable's selected-theme backend hard-requires Lazy. Replace only that
-- backend with native pack installation; keep its pickers and persisted lists.
local api = require 'huez-manager.api'
local registry = require 'huez-manager.registry'
local function selected_themes() return vim.list_extend(vim.deepcopy(api.ensured.installed), api.live.installed) end
local function install_huez_themes(themes)
  local installed_sources = {}
  for _, plugin in ipairs(vim.pack.get()) do
    installed_sources[plugin.spec.src] = true
  end
  local specs = {}
  for _, theme in ipairs(themes or selected_themes()) do
    local entry = assert(registry[theme], 'Huez theme missing from registry: ' .. theme)
    if not installed_sources[entry.url] then
      table.insert(specs, { src = entry.url, name = entry.pkgname })
      installed_sources[entry.url] = true
    end
  end
  if #specs > 0 then vim.pack.add(specs) end
  require('huez.config').load_theme_configs()
  -- Do not auto-delete previewed themes; remove unwanted ones with vim.pack.del.
end
package.loaded['huez-manager.api.selected'] = {
  selected = selected_themes,
  lazy_flush = install_huez_themes, -- Huez's internal callback name, not Lazy.
}
install_huez_themes()
require('huez').setup {
  fallback = 'tokyonight-night',
  picker = {
    live = { opts = { initial_mode = 'normal' } },
    ensured = { opts = { initial_mode = 'normal' } },
    themes = { opts = { initial_mode = 'normal' } },
    favorites = { opts = { initial_mode = 'normal' } },
  },
}
vim.keymap.set('n', '<leader>cs', '<cmd>Huez<cr>', { desc = '[C]olorscheme [S]elect' })
vim.keymap.set('n', '<leader>cl', '<cmd>HuezLive<cr>', { desc = '[C]olorscheme [L]ive registry' })
vim.keymap.set('n', '<leader>cf', '<cmd>HuezFavorites<cr>', { desc = '[C]olorscheme [F]avorites' })
vim.keymap.set('n', '<leader>ce', '<cmd>HuezEnsured<cr>', { desc = '[C]olorscheme [E]nsured' })

require('transparent').setup { extra_groups = { 'NormalFloat', 'FloatBorder', 'FoldColumn', 'WinSeparator' } }
vim.keymap.set('n', '<leader>tt', '<cmd>TransparentToggle<cr>', { desc = '[T]oggle [T]ransparency' })
