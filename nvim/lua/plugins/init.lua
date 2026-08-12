return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },
  {
    "nvim-tree/nvim-tree.lua",
    version = "*",
    lazy = false,
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("nvim-tree").setup {}
    end,
  },
  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },
  {
    "nvim-treesitter/nvim-treesitter",
    tag = "v0.9.3", -- Fixes Neovim < 0.12 compatibility
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" }, -- Load on buffer open
    cmd = { "TSInstall", "TSBufEnable", "TSBufDisable", "TSModuleInfo" },
    opts = {
      ensure_installed = {
        "vim",
        "lua",
        "vimdoc",
        "html",
        "css",
        "javascript",
        "typescript",
        "tsx",
        "markdown",        -- Required for headers/blocks
        "markdown_inline", -- Required for bold/italic/links
        "kotlin",
      },
      auto_install = true,
      config = function(_, opts)
        require("nvim-treesitter.configs").setup(opts)
      end,
      indent = {
        enable = true, -- Ensure treesitter handles unindenting
      },
    },
  },
  {
    "L3MON4D3/LuaSnip",
    config = function(_, opts)
      require("luasnip").config.set_config(opts)
      require("nvchad.configs.luasnip")
      require("configs.luasnip")
    end,
  },
}
