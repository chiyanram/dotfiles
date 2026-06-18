--- Java LSP (nvim-jdtls) with DAP support.
--- jdtls is managed by nvim-jdtls itself (ft=java FileType event), NOT by mason-lspconfig.
--- Mason ensures jdtls, java-debug-adapter and java-test are installed.

local function get_mason_pkg_path(name)
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    return nil
  end
  if not registry.is_installed(name) then
    return nil
  end
  return registry.get_package(name):get_install_path()
end

--- Collect DAP bundle jars from java-debug-adapter and java-test mason packages.
---@return string[]
local function get_dap_bundles()
  local bundles = {}

  local debug_path = get_mason_pkg_path("java-debug-adapter")
  if debug_path then
    vim.list_extend(bundles, vim.fn.globpath(debug_path .. "/extension/server", "com.microsoft.java.debug.plugin-*.jar", true, true))
  end

  local test_path = get_mason_pkg_path("java-test")
  if test_path then
    for _, jar in ipairs(vim.fn.globpath(test_path .. "/extension/server", "*.jar", true, true)) do
      table.insert(bundles, jar)
    end
  end

  return bundles
end

--- Detect the project root for Gradle/Maven/git projects.
---@return string|nil
local function find_root()
  return require("jdtls.setup").find_root({
    "gradlew",
    "mvnw",
    "settings.gradle",
    "settings.gradle.kts",
    "pom.xml",
    ".git",
  })
end

--- Build the jdtls launcher command from the mason-installed jdtls package.
--- Workspace is keyed off the resolved project root so two projects opened from
--- the same cwd never share a jdtls workspace (which corrupts jdtls state).
---@param root string|nil resolved project root (nil → loose .java file, fall back to cwd)
---@return string[]|nil
local function get_jdtls_cmd(root)
  local jdtls_path = get_mason_pkg_path("jdtls")
  if not jdtls_path then
    return nil
  end

  -- nvim-jdtls ships its own start script via the mason package
  local launcher = jdtls_path .. "/bin/jdtls"
  if vim.fn.filereadable(launcher) == 0 then
    return nil
  end

  -- Per-project workspace isolates caches so multiple projects don't collide.
  -- Use the resolved root when available; fall back to cwd for loose .java files.
  local base = root or vim.fn.getcwd()
  local project_name = vim.fn.fnamemodify(base, ":p:h:t")
  local workspace_dir = vim.fn.stdpath("cache") .. "/jdtls/" .. project_name

  return { launcher, "-data", workspace_dir }
end

--- Start or re-attach jdtls for the current buffer.
local function start_jdtls()
  -- Resolve root once so both the workspace name and root_dir are consistent.
  local root = find_root()

  local cmd = get_jdtls_cmd(root)
  if not cmd then
    vim.notify("jdtls not installed — run :MasonInstall jdtls", vim.log.levels.WARN)
    return
  end

  local bundles = get_dap_bundles()

  local lsp_utils = require("nisi.plugins.lsp.utils")
  local capabilities = lsp_utils.make_conf({}).capabilities

  local config = {
    cmd = cmd,
    root_dir = root or vim.fn.getcwd(),
    capabilities = capabilities,
    settings = {
      java = {
        configuration = {
          -- Let jdtls detect JDK from JAVA_HOME / PATH
          runtimes = {},
        },
        eclipse = { downloadSources = true },
        maven = { downloadSources = true },
        implementationsCodeLens = { enabled = true },
        referencesCodeLens = { enabled = true },
        references = { includeDecompiledSources = true },
        inlayHints = {
          parameterNames = { enabled = "all" },
        },
        format = { enabled = true },
      },
      signatureHelp = { enabled = true },
      completion = {
        favoriteStaticMembers = {
          "org.hamcrest.MatcherAssert.assertThat",
          "org.hamcrest.Matchers.*",
          "org.junit.jupiter.api.Assertions.*",
          "java.util.Objects.requireNonNull",
          "java.util.Objects.requireNonNullElse",
          "org.mockito.Mockito.*",
        },
        importOrder = { "java", "javax", "com", "org" },
      },
      sources = {
        organizeImports = {
          starThreshold = 9999,
          staticStarThreshold = 9999,
        },
      },
      codeGeneration = {
        toString = {
          template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
        },
        useBlocks = true,
      },
    },
    on_attach = function(client, bufnr)
      -- Wire up DAP after attach so debug commands are available immediately.
      if #bundles > 0 then
        require("jdtls").setup_dap({ hotcodereplace = "auto" })
        require("jdtls.dap").setup_dap_main_class_configs()
      end

      -- Java-specific buffer keymaps
      local function map(key, action, desc)
        vim.keymap.set("n", key, action, { buffer = bufnr, desc = desc, silent = true })
      end

      map("<leader>jo", "<cmd>lua require('jdtls').organize_imports()<cr>", "Organize imports")
      map("<leader>jv", "<cmd>lua require('jdtls').extract_variable()<cr>", "Extract variable")
      map("<leader>jc", "<cmd>lua require('jdtls').extract_constant()<cr>", "Extract constant")
      map("<leader>jt", "<cmd>lua require('jdtls.dap').test_nearest_method()<cr>", "Debug nearest test")
      map("<leader>jT", "<cmd>lua require('jdtls.dap').test_class()<cr>", "Debug test class")

      vim.keymap.set(
        "v",
        "<leader>jm",
        "<cmd>lua require('jdtls').extract_method(true)<cr>",
        { buffer = bufnr, desc = "Extract method", silent = true }
      )
    end,
    init_options = {
      bundles = bundles,
    },
  }

  require("jdtls").start_or_attach(config)
end

return {
  -- Ensure mason installs jdtls, java-debug-adapter and java-test.
  -- These are NOT lsp servers managed by mason-lspconfig; they are installed
  -- directly by mason-tool-installer and consumed by nvim-jdtls at runtime.
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = {
        "jdtls",
        "java-debug-adapter",
        "java-test",
        -- Terraform linter (not an lspconfig server)
        "tflint",
        -- YAML formatter
        "yamlfmt",
      },
      auto_update = false,
      run_on_start = true,
    },
  },

  -- nvim-jdtls: Java LSP + DAP client.
  -- Activated via FileType java — NOT through mason-lspconfig setup_handlers.
  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = {
      "mfussenegger/nvim-dap",
      "rcarriga/nvim-dap-ui",
      "WhoIsSethDaniel/mason-tool-installer.nvim",
    },
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "java",
        group = vim.api.nvim_create_augroup("NisiJdtls", { clear = true }),
        callback = start_jdtls,
      })
    end,
  },
}
