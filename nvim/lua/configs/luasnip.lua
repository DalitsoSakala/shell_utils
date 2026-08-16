-- lua/configs/luasnip.lua
local luasnip = require("luasnip")

-- Link React filetypes to standard JS/TS + HTML snippets
luasnip.filetype_extend("javascriptreact", { "html", "javascript" })
luasnip.filetype_extend("typescriptreact", { "html", "typescript" })

-- Android: expose the current file's package name as $PKG_NAME in snippets.
-- Derives the package from the file path, e.g.
--   .../app/src/main/java/com/example/foo/ui/Bar.kt  ->  com.example.foo.ui
-- Falls back to an empty string when the file is not under an Android
-- source root (java/kotlin) so `package $PKG_NAME` degrades gracefully.
luasnip.env_namespace("PKG", {
    init = function()
        local path = vim.fn.expand("%:p"):gsub("\\", "/")
        local markers = {
            "/app/src/main/java/",
            "/app/src/main/kotlin/",
            "/src/main/java/",
            "/src/main/kotlin/",
        }
        local name = ""
        for _, marker in ipairs(markers) do
            local idx = path:find(marker, 1, true)
            if idx then
                local rest = path:sub(idx + #marker)
                rest = rest:gsub("/[^/]+$", "")
                name = rest:gsub("/", ".")
                break
            end
        end
        return { NAME = name }
    end,
})

-- Load VS Code style snippets (friendly-snippets)
require("luasnip.loaders.from_vscode").lazy_load()

-- Load custom VS Code style snippets (including Jetpack Compose)
local snippets_path = vim.fn.stdpath("config") .. "/snippets"
require("luasnip.loaders.from_vscode").lazy_load({ paths = { snippets_path } })

