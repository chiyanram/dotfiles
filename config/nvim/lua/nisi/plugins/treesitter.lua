local config = require("nisi").config
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    version = false,
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "JoosepAlviste/nvim-ts-context-commentstring",
    },
    init = function(plugin)
      if config.prefer_git then
        require("nvim-treesitter.install").prefer_git = true
      end
      require("lazy.core.loader").add_to_rtp(plugin)
      require("nvim-treesitter.query_predicates")
    end,
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
      vim.treesitter.language.register("markdown", { "md", "mdx" })
    end,
    opts = {
      ensure_installed = {
        "bash",
        "c",
        "comment",
        "cpp",
        "diff",
        "git_rebase",
        "gitcommit",
        "gitignore",
        "html",
        "json",
        "jsonc",
        "lua",
        "markdown",
        "markdown_inline",
        "python",
        "regex",
        "rust",
        "vim",
        "yaml",
        -- Infrastructure & data
        "java",
        "hcl",
        "dockerfile",
        "sql",
      },
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = "gnn",
          node_incremental = "grn",
          scope_incremental = "grc",
          node_decremental = "grm",
        },
      },
      highlight = { enable = true, use_languagetree = true },
      indent = { enable = true },
      rainbow = { enable = true, extended_mode = true, max_file_lines = 1000 },
      textobjects = {
        select = {
          enable = true,
          lookahead = true, -- automatically jump forward to matching textobj
          keymaps = {
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
            ["ac"] = "@class.outer",
            ["ic"] = "@class.inner",
          },
        },
        swap = {
          enable = false,
          swap_next = { ["<leader>a"] = "@parameter.inner" },
          swap_previous = { ["<leader>A"] = "@parameter.inner" },
        },
      },
    },
  },
}
