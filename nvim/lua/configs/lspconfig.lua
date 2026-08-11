require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "vtsls", "emmet_ls" }
vim.lsp.enable(servers)

-- Ensure vtsls attaches to React filetypes
vim.lsp.config("vtsls", {
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
})

-- Force Neovim hover windows to use basic regex markdown instead of Treesitter
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(
  vim.lsp.handlers.hover, {
    syntax = "markdown",
  }
)

for _, lsp in ipairs(servers) do
  local opts = {
    on_attach = configs.on_attach,
    capabilities = configs.capabilities,
  }
  
  if lsp == "emmet_ls" then
    opts.filetypes = { "html", "css", "scss", "javascript", "typescript", "typescriptreact", "javascriptreact" }
  end

  require("lspconfig")[lsp].setup(opts)
end

