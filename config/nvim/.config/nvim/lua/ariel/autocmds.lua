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
    -- Starts preview on a random port, opens in Chrome Canary, zooms tmux pane
    -- Kills any existing preview server before starting a new one to avoid multiple processes
    vim.keymap.set("n", "<leader>mp", function()
      if vim.g.markdown_preview_job then
        vim.fn.jobstop(vim.g.markdown_preview_job)
      end
      -- Pick a random available port
      local port = math.random(10000, 60000)
      vim.g.markdown_preview_port = port
      vim.g.markdown_preview_job = vim.fn.jobstart({
        "gh",
        "markdown-preview",
        "--disable-auto-open",
        "--port",
        tostring(port),
        vim.fn.expand("%:p"),
      })
      -- Wait for server to start, then open in Chrome Canary and zoom tmux pane
      vim.defer_fn(function()
        -- Open preview in Chrome Canary (aerospace will tile it automatically)
        vim.fn.jobstart({ "open", "-a", "Google Chrome Canary", "http://localhost:" .. port })
        -- Zoom tmux pane only if not already zoomed, track that we did it
        local zoomed = vim.fn.system("tmux display-message -p '#{window_zoomed_flag}'"):gsub("%s+", "")
        if zoomed == "0" then
          vim.fn.jobstart({ "tmux", "resize-pane", "-Z" })
          vim.g.markdown_preview_zoomed = true
        end
      end, 500)
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

    -- Clean up: Kill preview server, close Chrome tab, unzoom pane, restore layout
    -- Triggered when switching buffers, closing buffer, or Neovim exits
    vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete", "BufUnload", "VimLeave" }, {
      buffer = 0,
      callback = function()
        if vim.g.markdown_preview_job then
          -- Kill preview server
          vim.fn.jobstop(vim.g.markdown_preview_job)
          vim.g.markdown_preview_job = nil
          -- Close Chrome Canary tab at the specific port
          local port = vim.g.markdown_preview_port
          if port then
            vim.fn.jobstart({
              "osascript",
              "-e",
              'tell application "Google Chrome Canary" to close (windows whose URL of active tab starts with "http://localhost:'
                .. port
                .. '")',
            })
            vim.g.markdown_preview_port = nil
          end
          -- Unzoom tmux pane if we zoomed it
          if vim.g.markdown_preview_zoomed then
            vim.fn.jobstart({ "tmux", "resize-pane", "-Z" })
            vim.g.markdown_preview_zoomed = nil
          end
        end
      end,
    })
  end,
})
