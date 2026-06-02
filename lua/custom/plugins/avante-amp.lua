local function claude_acp_adapter()
  if vim.fn.executable 'claude-agent-acp' == 1 then
    return { command = 'claude-agent-acp', args = {} }
  end

  if vim.fn.executable 'npx' == 1 and vim.fn.executable 'claude' == 1 then
    return { command = 'npx', args = { '-y', '@agentclientprotocol/claude-agent-acp' } }
  end

  return nil
end

local function codex_acp_adapter()
  if vim.fn.executable 'codex-acp' == 1 then
    return { command = 'codex-acp', args = {} }
  end

  return nil
end

local claude_adapter = claude_acp_adapter()
local codex_adapter = codex_acp_adapter()
local avante_debug = vim.env.AVANTE_DEBUG == '1'
local default_provider = claude_adapter and 'claude-code' or codex_adapter and 'codex'

local function executable_status(command)
  if vim.fn.executable(command) == 1 then
    return vim.fn.exepath(command)
  end

  return 'missing'
end

return {
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    version = false,
    build = 'make',
    init = function()
      vim.api.nvim_create_user_command('AvanteAcpHealth', function()
        local log_dir = vim.fn.stdpath 'log'
        local lines = {
          'Avante ACP provider: ' .. default_provider,
          'claude: ' .. executable_status 'claude',
          'claude-agent-acp: ' .. executable_status 'claude-agent-acp',
          'npx: ' .. executable_status 'npx',
          'Claude ACP package: @agentclientprotocol/claude-agent-acp',
          'codex-acp: ' .. executable_status 'codex-acp',
          'avante.log: ' .. vim.fs.joinpath(log_dir, 'avante.log'),
          'avante-acp-session.log: ' .. vim.fs.joinpath(log_dir, 'avante-acp-session.log'),
          'Set AVANTE_DEBUG=1 before starting nvim to write ACP JSON-RPC logs.',
        }

        vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'Avante ACP Health' })
      end, { desc = 'Show Avante ACP provider diagnostics' })

      vim.api.nvim_create_user_command('AvanteAcpReset', function()
        pcall(function()
          local avante = require 'avante'
          if avante.cleanup_all_acp_clients then
            avante.cleanup_all_acp_clients()
          end
        end)

        local history_root = vim.fs.joinpath(vim.fn.stdpath 'state', 'avante', 'projects')
        local pattern = vim.fs.joinpath(history_root, '**', 'history', '*.json')
        local cleared = 0

        for _, file in ipairs(vim.fn.glob(pattern, true, true)) do
          if not file:match 'metadata%.json$' then
            local content = table.concat(vim.fn.readfile(file), '\n')
            local ok, history = pcall(vim.json.decode, content)
            if ok and type(history) == 'table' and history.acp_session_id ~= nil then
              history.acp_session_id = nil
              vim.fn.writefile({ vim.json.encode(history) }, file)
              cleared = cleared + 1
            end
          end
        end

        vim.notify(('Cleared %d persisted Avante ACP session id(s). Run :AvanteChatNew or send a fresh prompt.'):format(cleared), vim.log.levels.INFO, { title = 'Avante ACP Reset' })
      end, { desc = 'Clear persisted Avante ACP session ids' })
    end,
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-tree/nvim-web-devicons',
      {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = function(_, opts)
          opts.file_types = opts.file_types or { 'markdown' }
          if not vim.tbl_contains(opts.file_types, 'Avante') then
            table.insert(opts.file_types, 'Avante')
          end
        end,
      },
    },
    keys = {
      { '<leader>av', '<cmd>AvanteToggle<cr>', desc = '[A]I A[v]ante toggle' },
      { '<leader>ai', '<cmd>AvanteAsk<cr>', mode = { 'n', 'v' }, desc = '[A]I Avante ask' },
      { '<leader>ae', '<cmd>AvanteEdit<cr>', mode = 'v', desc = '[A]I Avante edit selection' },
      { '<leader>aR', '<cmd>AvanteRefresh<cr>', desc = '[A]I Avante refresh' },
      { '<leader>aS', '<cmd>AvanteStop<cr>', desc = '[A]I Avante stop' },
    },
    opts = {
      provider = default_provider,
      mode = 'agentic',
      debug = avante_debug,
      log_level = avante_debug and vim.log.levels.DEBUG or vim.log.levels.WARN,
      acp_providers = {
        ['claude-code'] = claude_adapter and {
          command = claude_adapter.command,
          args = claude_adapter.args,
          env = {
            NODE_NO_WARNINGS = '1',
            ACP_DEBUG = avante_debug and 'true' or nil,
            ACP_PATH_TO_CLAUDE_CODE_EXECUTABLE = vim.fn.exepath 'claude',
            ACP_PERMISSION_MODE = 'acceptEdits',
            HOME = vim.env.HOME,
            LOGNAME = vim.env.LOGNAME,
            PATH = vim.env.PATH,
            SHELL = vim.env.SHELL,
            USER = vim.env.USER,
          },
        } or nil,
        codex = codex_adapter and {
          command = codex_adapter.command,
          args = codex_adapter.args,
          env = {
            NODE_NO_WARNINGS = '1',
            OPENAI_API_KEY = vim.env.OPENAI_API_KEY,
            HOME = vim.env.HOME,
            PATH = vim.env.PATH,
          },
        } or nil,
      },
      behaviour = {
        auto_suggestions = false,
        auto_set_highlight_group = true,
        auto_set_keymaps = false,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
      },
      selector = {
        provider = 'fzf_lua',
      },
      input = {
        provider = 'native',
      },
      windows = {
        width = 42,
        sidebar_header = {
          enabled = true,
          align = 'center',
          rounded = true,
        },
      },
    },
  },
}
