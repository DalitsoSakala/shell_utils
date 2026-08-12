-- lua/configs/luasnip.lua
local luasnip = require("luasnip")

-- Link React filetypes to standard JS/TS + HTML snippets
luasnip.filetype_extend("javascriptreact", { "html", "javascript" })
luasnip.filetype_extend("typescriptreact", { "html", "typescript" })

-- Load VS Code style snippets (friendly-snippets)
require("luasnip.loaders.from_vscode").lazy_load()

-- Load custom VS Code style snippets (including Jetpack Compose)
local snippets_path = vim.fn.stdpath("config") .. "/snippets"
require("luasnip.loaders.from_vscode").lazy_load({ paths = { snippets_path } })

