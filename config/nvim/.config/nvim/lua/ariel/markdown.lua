-- Preview the current buffer with leaf in a full-screen tmux popup.
local function leaf_popup()
  if not vim.env.TMUX then
    vim.notify("leaf preview needs tmux", vim.log.levels.WARN)
    return
  end
  if vim.bo.filetype ~= "markdown" then
    vim.notify("leaf preview is for markdown files", vim.log.levels.WARN)
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("Save the buffer before previewing", vim.log.levels.WARN)
    return
  end
  vim.fn.jobstart({
    "tmux",
    "popup",
    "-d",
    vim.fn.fnamemodify(file, ":h"),
    "-w100%",
    "-h100%",
    "-E",
    "leaf " .. vim.fn.shellescape(file),
  })
end

vim.keymap.set("n", "<leader>mp", leaf_popup, { desc = "Preview file with leaf (tmux popup)" })
