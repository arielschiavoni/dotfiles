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

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "aerospace.toml" },
  command = "!aerospace reload-config",
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "yazi.toml" },
  command = "execute 'silent !yazi --clear-cache'",
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "config.fish" },
  command = "execute 'silent !source <afile> --silent'",
})

-- Markdown file keybindings
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    -- <C-Space>: Toggle checkbox state between [ ] and [x]
    -- Useful for task lists in markdown files
    vim.keymap.set("n", "<C-Space>", function()
      local line = vim.api.nvim_get_current_line()
      if string.match(line, "%[ %]") then
        line = string.gsub(line, "%[ %]", "[x]")
      elseif string.match(line, "%[x%]") then
        line = string.gsub(line, "%[x%]", "[ ]")
      end
      vim.api.nvim_set_current_line(line)
    end, { buffer = true, desc = "Toggle checkbox" })
  end,
})
