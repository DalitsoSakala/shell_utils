-- File: ~/.config/nvim/lua/plugins/treesitter.lua

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      -- Change ".configs" to ".config" here:
      require("nvim-treesitter.config").setup({
        ensure_installed = { "javascript", "typescript", "tsx", "html", "css" },
        highlight = { 
          enable = true,
          additional_vim_regex_highlighting = false,
        },
      })
    end
  }
}
