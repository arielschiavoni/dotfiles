require("user.core.settings")
require("user.core.keymaps")
require("user.core.plugins")

-- temporarly highlight yankend region.
-- it helps to visualise what was yanked after running commands like: ya{
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("HighlightYank", {}),
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({
      higroup = "IncSearch",
      timeout = 150,
    })
  end,
})
