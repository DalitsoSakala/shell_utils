-- File: ~/.config/nvim/lua/plugins/lsp.lua

return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      -- Mason manages the local installation of LSP binaries
      { "williamboman/mason.nvim", config = true },
      { "williamboman/mason-lspconfig.nvim" },
    },
    config = function()
      -- 1. Ensure Mason installs our chosen non-JS servers (vtsls is removed)
      require("mason-lspconfig").setup({
        ensure_installed = { "tailwindcss", "html", "cssls" }
      })

      -- 2. Configure our active LSPs (Tailwind, HTML, CSS)
      -- Uses the modern Neovim 0.11+ API with a legacy fallback for 0.10
      if vim.lsp.config then
        -- Neovim 0.11+ syntax
        vim.lsp.enable("tailwindcss")
        vim.lsp.enable("html")
        vim.lsp.enable("cssls")
      else
        -- Legacy fallback (Neovim 0.10 and older)
        local lspconfig = require("lspconfig")
        
        lspconfig.tailwindcss.setup({})
        lspconfig.html.setup({})
        lspconfig.cssls.setup({})
      end

      -- 3. Global LSP Keymaps (Active when any LSP connects)
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local opts = { buffer = ev.buf }
          local map = vim.keymap.set

          map("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to Definition" }))
          map("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover Docs" }))
          map("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code Action" }))
          map("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename Symbol" }))
          map("n", "[d", vim.diagnostic.goto_prev, vim.tbl_extend("force", opts, { desc = "Prev Diagnostic" }))
          map("n", "]d", vim.diagnostic.goto_next, vim.tbl_extend("force", opts, { desc = "Next Diagnostic" }))
        end,
      })
    end
  }
}
