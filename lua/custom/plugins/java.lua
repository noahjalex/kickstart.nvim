local function jdtls_cmd()
  local mason_jdtls = vim.fn.stdpath 'data' .. '/mason/bin/jdtls'
  if vim.fn.executable(mason_jdtls) == 1 then
    return mason_jdtls
  end

  local path_jdtls = vim.fn.exepath 'jdtls'
  if path_jdtls ~= '' then
    return path_jdtls
  end

  return 'jdtls'
end

local function workspace_dir(root_dir)
  local root = vim.fn.fnamemodify(root_dir, ':p'):gsub('/$', '')
  local project_name = vim.fn.fnamemodify(root, ':t')
  local project_hash = vim.fn.sha256(root):sub(1, 8)
  local dir = table.concat({ vim.fn.stdpath 'data', 'jdtls-workspaces', project_name .. '-' .. project_hash }, '/')

  vim.fn.mkdir(dir, 'p')

  return dir
end

return {
  {
    'mfussenegger/nvim-jdtls',
    ft = 'java',
    dependencies = {
      'mason-org/mason.nvim',
      'saghen/blink.cmp',
    },
    config = function()
      local function start_jdtls()
        local jdtls = require 'jdtls'
        local root_dir = jdtls.setup.find_root {
          'settings.gradle',
          'settings.gradle.kts',
          'pom.xml',
          'build.gradle',
          'build.gradle.kts',
          'mvnw',
          'gradlew',
          '.git',
        }

        if not root_dir then
          return
        end

        local capabilities = vim.lsp.protocol.make_client_capabilities()
        local ok, blink = pcall(require, 'blink.cmp')
        if ok then
          capabilities = blink.get_lsp_capabilities(capabilities)
        end

        jdtls.start_or_attach {
          cmd = {
            jdtls_cmd(),
            '-data',
            workspace_dir(root_dir),
          },
          root_dir = root_dir,
          capabilities = capabilities,
          settings = {
            java = {
              configuration = {
                updateBuildConfiguration = 'interactive',
              },
              import = {
                gradle = {
                  enabled = true,
                  wrapper = {
                    enabled = true,
                  },
                },
                maven = {
                  enabled = true,
                },
              },
            },
          },
        }
      end

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('custom-java-jdtls', { clear = true }),
        pattern = 'java',
        callback = start_jdtls,
      })

      start_jdtls()
    end,
  },
}
