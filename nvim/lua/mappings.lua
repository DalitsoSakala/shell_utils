require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Copy absolute file path
map("n", "<leader>cp", function()
  local path = vim.api.nvim_buf_get_name(0)
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path)
end, { desc = "Copy absolute file path" })

-- Copy relative file path
map("n", "<leader>cr", function()
  local path = vim.fn.expand("%")
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path)
end, { desc = "Copy relative file path" })

-- Show floating git blame details for current line
map("n", "<leader>gb", function()
  require("gitsigns").blame_line({ full = true })
end, { desc = "Git blame current line" })

-- Toggle inline ghost text blame
map("n", "<leader>tb", function()
  require("gitsigns").toggle_current_line_blame({ full = true })
end, { desc = "Toggle inline git blame" })

-- Open file state at the current line's git blame commit
map("n", "<leader>gC", function()
  require("gitsigns").blame_line({ full = false }, function()
    -- Extract commit hash from gitsigns blame line popup
    local blame_win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(blame_win)
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    local commit = line:match("^%x+")

    if commit and commit ~= "00000000" then
      vim.cmd("tabnew | Gitsigns show " .. commit)
    else
      print("No committed state found for this line.")
    end
  end)
end, { desc = "Open file state at blame commit" })
-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
