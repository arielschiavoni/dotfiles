-- temporarly highlight yankend region.
-- it helps to visualise what was yanked after running commands like: ya{
vim.api.nvim_create_autocmd("TextYankPost", {
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({
      higroup = "IncSearch",
      timeout = 150,
    })
  end,
})
