return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'leoluz/nvim-dap-go',
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
  },
  keys = {
    {
      '<F5>',
      function()
        require('dap').continue()
      end,
      desc = 'Debug: Start/Continue',
    },
    {
      '<F10>',
      function()
        require('dap').step_over()
      end,
      desc = 'Debug: Step Over',
    },
    {
      '<F11>',
      function()
        require('dap').step_into()
      end,
      desc = 'Debug: Step Into',
    },
    {
      '<F12>',
      function()
        require('dap').step_out()
      end,
      desc = 'Debug: Step Out',
    },
    {
      '<leader>db',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = '[D]ebug Toggle [B]reakpoint',
    },
    {
      '<leader>dB',
      function()
        require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
      end,
      desc = '[D]ebug Conditional [B]reakpoint',
    },
    {
      '<leader>dc',
      function()
        require('dap').continue()
      end,
      desc = '[D]ebug [C]ontinue',
    },
    {
      '<leader>dl',
      function()
        require('dap').run_last()
      end,
      desc = '[D]ebug Run [L]ast',
    },
    {
      '<leader>dr',
      function()
        require('dap').repl.open()
      end,
      desc = '[D]ebug [R]EPL',
    },
    {
      '<leader>dt',
      function()
        require('dap').terminate()
      end,
      desc = '[D]ebug [T]erminate',
    },
    {
      '<leader>du',
      function()
        require('dapui').toggle()
      end,
      desc = '[D]ebug Toggle [U]I',
    },
    {
      '<leader>de',
      function()
        require('dapui').eval()
      end,
      mode = { 'n', 'v' },
      desc = '[D]ebug [E]valuate',
    },
    {
      '<leader>dg',
      function()
        require('dap-go').debug_test()
      end,
      desc = '[D]ebug [G]o Test',
    },
    {
      '<leader>dG',
      function()
        require('dap-go').debug_last_test()
      end,
      desc = '[D]ebug Last [G]o Test',
    },
  },
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'
    local signs = vim.g.have_nerd_font
        and {
          Breakpoint = '',
          BreakpointCondition = '',
          BreakpointRejected = '',
          LogPoint = '',
          Stopped = '',
        }
      or {
        Breakpoint = '●',
        BreakpointCondition = '⊜',
        BreakpointRejected = '⊘',
        LogPoint = '◆',
        Stopped = '⭔',
      }

    vim.api.nvim_set_hl(0, 'DapBreakpoint', { fg = '#e51400' })
    vim.api.nvim_set_hl(0, 'DapStopped', { fg = '#ffcc00' })

    for name, icon in pairs(signs) do
      local hl = name == 'Stopped' and 'DapStopped' or 'DapBreakpoint'
      vim.fn.sign_define('Dap' .. name, { text = icon, texthl = hl, numhl = hl })
    end

    dap.defaults.fallback.terminal_win_cmd = 'belowright 15split new'

    dapui.setup {
      icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
      controls = {
        icons = {
          pause = '⏸',
          play = '▶',
          step_into = '⏎',
          step_over = '⏭',
          step_out = '⏮',
          step_back = 'b',
          run_last = '▶▶',
          terminate = '⏹',
          disconnect = '⏏',
        },
      },
    }

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close

    require('dap-go').setup {
      delve = {
        path = vim.fn.stdpath 'data' .. '/mason/bin/dlv',
        detached = vim.fn.has 'win32' == 0,
      },
    }

    dap.adapters.codelldb = {
      type = 'server',
      port = '${port}',
      executable = {
        command = vim.fn.stdpath 'data' .. '/mason/bin/codelldb',
        args = { '--port', '${port}' },
      },
    }

    local function zig_root()
      local source = vim.api.nvim_buf_get_name(0)
      local start = source ~= '' and vim.fs.dirname(source) or vim.uv.cwd()
      local build_zig = vim.fs.find('build.zig', { path = start, upward = true })[1]

      return build_zig and vim.fs.dirname(build_zig) or vim.uv.cwd()
    end

    local function zig_project_name(root)
      local build_zig = root .. '/build.zig'
      if vim.fn.filereadable(build_zig) == 0 then
        return vim.fn.fnamemodify(root, ':t')
      end

      for _, line in ipairs(vim.fn.readfile(build_zig)) do
        local name = line:match '%.name%s*=%s*"([^"]+)"'
        if name then
          return name
        end
      end

      return vim.fn.fnamemodify(root, ':t')
    end

    local function newest_zig_binary(root)
      local files = vim.fn.glob(root .. '/zig-out/bin/*', true, true)

      table.sort(files, function(a, b)
        local stat_a = vim.uv.fs_stat(a)
        local stat_b = vim.uv.fs_stat(b)

        return stat_a and stat_b and stat_a.mtime.sec > stat_b.mtime.sec
      end)

      for _, file in ipairs(files) do
        local stat = vim.uv.fs_stat(file)
        if stat and stat.type == 'file' and vim.fn.executable(file) == 1 then
          return file
        end
      end
    end

    local function zig_program()
      local root = zig_root()
      local name = zig_project_name(root)
      local default_program = root .. '/zig-out/bin/' .. name

      if vim.fn.executable 'zig' ~= 1 then
        vim.notify('zig executable not found', vim.log.levels.ERROR)
        return vim.fn.input('Path to executable: ', default_program, 'file')
      end

      vim.notify('Running zig build...', vim.log.levels.INFO)

      local result = vim.system({ 'zig', 'build' }, { cwd = root, text = true }):wait()
      if result.code ~= 0 then
        vim.notify(result.stderr ~= '' and result.stderr or result.stdout, vim.log.levels.ERROR)
        return vim.fn.input('Path to executable: ', default_program, 'file')
      end

      if vim.fn.executable(default_program) == 1 then
        return default_program
      end

      return newest_zig_binary(root) or vim.fn.input('Path to executable: ', root .. '/zig-out/bin/', 'file')
    end

    dap.configurations.zig = {
      {
        name = 'Build and launch Zig executable',
        type = 'codelldb',
        request = 'launch',
        program = zig_program,
        cwd = zig_root,
        stopOnEntry = false,
      },
    }
  end,
}
