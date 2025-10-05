local function new_daily_entry()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local new_date = os.date("%a %b %d %Y")
  local insert_pos = 2 -- After "# Daily\n\n"

  -- Check if current date section already exists
  for i = insert_pos, #lines do
    if lines[i] == "## " .. new_date then
      vim.notify("Today's entry ('" .. new_date .. "') already exists.", vim.log.levels.INFO)
      return
    end
  end

  -- Find start of previous section (first "## " after title)
  local prev_start = nil
  for i = insert_pos, #lines do
    if lines[i]:match("^## ") then
      prev_start = i
      break
    end
  end
  if not prev_start then
    vim.notify("No previous day section found.", vim.log.levels.WARN)
    return
  end

  -- Find end of previous section (before next "## " or end)
  local section_end = prev_start + 1
  while section_end <= #lines and not lines[section_end]:match("^## ") do
    section_end = section_end + 1
  end

  -- Collect undone tasks from previous section (after header)
  local undone_tasks = {}
  local undone_indices = {}
  for i = prev_start + 1, section_end - 1 do
    local line = lines[i]
    if line:match("^%s*- ") and line:match("%[ %]") then -- Undone: "- [ ]"
      table.insert(undone_tasks, line)
      table.insert(undone_indices, i)
    end
  end

  -- Delete undone tasks (sort descending to avoid index shifts)
  table.sort(undone_indices, function(a, b)
    return a > b
  end)
  for _, idx in ipairs(undone_indices) do
    vim.api.nvim_buf_set_lines(0, idx - 1, idx, false, {})
  end

  -- Build and insert new section
  local new_section = { "## " .. new_date, "" }
  for _, task in ipairs(undone_tasks) do
    table.insert(new_section, task)
  end
  table.insert(new_section, "") -- Trailing empty before old section

  vim.api.nvim_buf_set_lines(0, insert_pos, insert_pos, false, new_section)
  vim.notify("New daily entry added with " .. #undone_tasks .. " undone tasks moved.", vim.log.levels.INFO)
end

local function open_daily_notes()
  vim.cmd.edit("~/Documents/notes/notes.md")
  new_daily_entry()
end

vim.keymap.set("n", "<leader>do", open_daily_notes, { desc = "Open daily notes" })

vim.keymap.set("n", "<leader>da", new_daily_entry, { desc = "Add new daily entry and move undone tasks" })
