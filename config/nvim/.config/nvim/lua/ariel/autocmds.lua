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

-- Markdown file keybindings and preview management
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    -- <leader>mp: Preview markdown in browser using 'gh markdown-preview'
    -- Kills any existing preview server before starting a new one to avoid multiple processes
    vim.keymap.set("n", "<leader>mp", function()
      if vim.g.markdown_preview_job then
        vim.fn.jobstop(vim.g.markdown_preview_job)
      end
      vim.g.markdown_preview_job = vim.fn.jobstart({ "gh", "markdown-preview", vim.fn.expand("%:p") })
    end, { buffer = true, desc = "Markdown preview (gh)" })

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

    -- Clean up: Kill preview server when switching buffers, closing buffer, or Neovim exits
    -- Prevents orphaned 'gh markdown-preview' background processes
    vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete", "BufUnload", "VimLeave" }, {
      buffer = 0,
      callback = function()
        if vim.g.markdown_preview_job then
          vim.fn.jobstop(vim.g.markdown_preview_job)
          vim.g.markdown_preview_job = nil
        end
      end,
    })
  end,
})
