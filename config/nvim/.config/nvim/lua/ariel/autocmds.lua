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
    -- <leader>mp: Toggle markdown preview (open/close leaf in right pane)
    -- Opens leaf in right split, moving other panes to temp window
    -- Press again to close and restore original pane layout
    vim.keymap.set("n", "<leader>mp", function()
      if vim.g.leaf_active then
        -- Close preview: kill leaf pane, restore moved panes in order, restore layout
        vim.fn.system({ "tmux", "kill-pane", "-t", vim.g.leaf_pane_id })

        -- Restore moved panes back to original window, chaining horizontally to the right
        local last_pane = vim.g.leaf_current_pane
        if vim.g.leaf_moved_panes and #vim.g.leaf_moved_panes > 0 then
          for _, pane_id in ipairs(vim.g.leaf_moved_panes) do
            vim.fn.system({ "tmux", "move-pane", "-h", "-s", pane_id, "-t", last_pane })
            last_pane = pane_id
          end
        end

        -- Kill the temporary window (removes its empty initial shell pane)
        vim.fn.system({ "tmux", "kill-window", "-t", "leaf-temp" })

        -- Restore original layout (fixes pane sizes to exact original dimensions)
        vim.fn.system({ "tmux", "select-layout", "-t", vim.g.leaf_window, vim.g.leaf_original_layout })

        -- Clear state
        vim.g.leaf_active = nil
        vim.g.leaf_window = nil
        vim.g.leaf_current_pane = nil
        vim.g.leaf_pane_id = nil
        vim.g.leaf_moved_panes = nil
        vim.g.leaf_original_layout = nil
      else
        -- Open preview: capture state, move other panes, create leaf split
        local file = vim.fn.expand("%:p")
        local current_pane = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub("%s+", "")
        local current_window = vim.fn.system("tmux display-message -p '#{window_id}'"):gsub("%s+", "")
        local current_window_name = vim.fn.system("tmux display-message -p '#{window_name}'"):gsub("%s+", "")
        local original_layout = vim.fn.system("tmux display-message -p '#{window_layout}'"):gsub("%s+", "")

        -- Move non-current panes to temp window, tracking them in order
        -- Use break-pane for first pane (creates leaf-temp with no empty shell pane)
        -- Use move-pane for remaining panes
        local moved_panes = {}
        local all_panes =
          vim.fn.system("tmux list-panes -t " .. current_window_name .. " -F '#{pane_id}' 2>/dev/null"):gsub("\n$", "")
        local first = true
        for pane_id in all_panes:gmatch("[^\n]+") do
          if pane_id ~= current_pane then
            if first then
              -- Break first pane into new leaf-temp window (no empty shell pane)
              vim.fn.system({ "tmux", "break-pane", "-d", "-n", "leaf-temp", "-s", pane_id })
              first = false
            else
              -- Move subsequent panes into leaf-temp
              vim.fn.system({ "tmux", "move-pane", "-s", pane_id, "-t", "leaf-temp" })
            end
            table.insert(moved_panes, pane_id)
          end
        end

        -- Re-focus original pane (break-pane and move-pane steal focus)
        vim.fn.system({ "tmux", "select-window", "-t", current_window })
        vim.fn.system({ "tmux", "select-pane", "-t", current_pane })

        -- Open leaf in right split and capture new pane ID
        local split_output =
          vim.fn.system({ "tmux", "split-window", "-h", "-P", "-F", "#{pane_id}", "-t", current_pane, "leaf", file })
        local leaf_pane_id = split_output:gsub("%s+", "")

        -- Re-focus editor pane (split-window steals focus)
        vim.fn.system({ "tmux", "select-pane", "-t", current_pane })

        -- Store all state for restoration
        vim.g.leaf_window = current_window
        vim.g.leaf_current_pane = current_pane
        vim.g.leaf_pane_id = leaf_pane_id
        vim.g.leaf_moved_panes = moved_panes
        vim.g.leaf_original_layout = original_layout
        vim.g.leaf_active = true
      end
    end, { buffer = true, desc = "Toggle markdown preview (leaf)" })

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
