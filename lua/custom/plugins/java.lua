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

local function java_home(version)
  local home = vim.fn.systemlist { '/usr/libexec/java_home', '-v', version }
  if vim.v.shell_error == 0 and home[1] and home[1] ~= '' then
    return home[1]
  end
end

local function path_join(...)
  return table.concat({ ... }, '/')
end

local function marker_dir(start_dir, markers)
  local dir = vim.fn.fnamemodify(start_dir, ':p'):gsub('/$', '')

  while dir and dir ~= '/' do
    for _, marker in ipairs(markers) do
      if vim.uv.fs_stat(path_join(dir, marker)) then
        return dir
      end
    end

    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      return nil
    end

    dir = parent
  end

  return nil
end

local function project_root()
  local source = vim.api.nvim_buf_get_name(0)
  local start_dir = source ~= '' and vim.fn.fnamemodify(source, ':p:h') or vim.uv.cwd()

  -- Put a `.jdtls-root` file or directory in a monorepo subproject when the
  -- repository root is too broad for one useful Java workspace.
  return marker_dir(start_dir, { '.jdtls-root' })
    or marker_dir(start_dir, { 'settings.gradle', 'settings.gradle.kts', 'mvnw', 'gradlew' })
    or marker_dir(start_dir, { 'pom.xml', 'build.gradle', 'build.gradle.kts' })
    or marker_dir(start_dir, { '.git' })
end

local function workspace_dir(root_dir)
  local root = vim.fn.fnamemodify(root_dir, ':p'):gsub('/$', '')
  local project_name = vim.fn.fnamemodify(root, ':t')
  local project_hash = vim.fn.sha256(root):sub(1, 8)
  local dir = path_join(vim.fn.stdpath 'data', 'jdtls-workspaces', project_name .. '-' .. project_hash)

  vim.fn.mkdir(dir, 'p')

  return dir
end

local function shared_index_dir()
  local dir = path_join(vim.fn.stdpath 'cache', 'jdtls-index')

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
        local root_dir = project_root()

        if not root_dir then
          return
        end

        local capabilities = vim.lsp.protocol.make_client_capabilities()
        local ok, blink = pcall(require, 'blink.cmp')
        if ok then
          capabilities = blink.get_lsp_capabilities(capabilities)
        end

        -- JDTLS and older Gradle wrappers currently fail when launched under
        -- Java 25. Pin the editor-side Java tooling to Java 21 when available.
        local java21_home = java_home '21'

        jdtls.start_or_attach {
          cmd = {
            jdtls_cmd(),
            '-data',
            workspace_dir(root_dir),
          },
          cmd_env = java21_home and {
            JAVA_HOME = java21_home,
            PATH = java21_home .. '/bin:' .. vim.env.PATH,
          } or nil,
          root_dir = root_dir,
          capabilities = capabilities,
          settings = {
            java = {
              autobuild = {
                enabled = false,
              },
              configuration = {
                updateBuildConfiguration = 'interactive',
                workspaceCacheLimit = 90,
              },
              maxConcurrentBuilds = 1,
              project = {
                importOnFirstTimeStartup = 'interactive',
                resourceFilters = {
                  'node_modules',
                  '\\.git',
                  '\\.gradle',
                  'bazel-.*',
                  'build',
                  'target',
                  'out',
                  'dist',
                  'tmp',
                },
              },
              import = {
                exclusions = {
                  '**/node_modules/**',
                  '**/.metadata/**',
                  '**/archetype-resources/**',
                  '**/META-INF/maven/**',
                  '**/bazel-*/**',
                  '**/build/**',
                  '**/target/**',
                },
                gradle = {
                  enabled = true,
                  java = java21_home and {
                    home = java21_home,
                  } or nil,
                  wrapper = {
                    enabled = true,
                  },
                },
                maven = {
                  enabled = true,
                },
              },
              sharedIndexes = {
                enabled = 'auto',
                location = shared_index_dir(),
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
