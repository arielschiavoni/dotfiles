-- Send neovim context to a pi agent running in a tmux pane.
-- Pastes into pi's prompt without submitting (send.append_newline = false),
-- so the message can still be reviewed and edited before hitting enter.
local function send(msg)
  local ps = require("pi_send")

  local text = ps.render({ msg = msg })
  if not text then
    vim.notify("Nothing to send to pi", vim.log.levels.WARN)
    return
  end

  -- The plugin itself does not match on directory: with a single pi pane it
  -- sends there unconditionally, even when it belongs to another project.
  -- Prefer a pane whose cwd contains ours, and fall back to the picker.
  local ok, panes = pcall(ps.panes)
  if ok then
    local cwd = vim.uv.cwd()
    local matches = vim.tbl_filter(function(pane)
      return pane.cwd ~= "" and vim.startswith(cwd, pane.cwd)
    end, panes)

    if #matches == 1 then
      local sent, err = pcall(require("pi_send.tmux").send, matches[1], text)
      if sent then
        vim.notify("Appended to pi prompt (" .. matches[1].cwd .. ")")
      else
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
      return
    end
  end

  ps.send({ msg = msg })
end

return {
  "SavingFrame/pi-send.nvim",
  main = "pi_send",
  opts = {
    send = {
      -- Do not append a trailing newline: tmux pastes the text into pi's
      -- prompt and leaves it there instead of submitting the turn.
      append_newline = false,
    },
    tmux = {
      current_session_only = true,
    },
  },
  -- stylua: ignore start
  keys = {
    { "<leader>ia", function() send("{this}") end,      mode = { "n", "x" }, desc = "Append context to pi" },
    { "<leader>is", function() send("{selection}") end, mode = "x",          desc = "Append selection to pi" },
    { "<leader>if", function() send("{file}") end,                           desc = "Append file to pi" },
    { "<leader>il", function() send("{line}") end,                           desc = "Append line to pi" },
    { "<leader>ip", function() require("pi_send").send({ msg = "{this}" }) end, mode = { "n", "x" }, desc = "Append context to pi (pick pane)" },
  },
  -- stylua: ignore end
}
