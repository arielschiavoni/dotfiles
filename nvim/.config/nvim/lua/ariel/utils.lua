local reload_module = require("plenary.reload").reload_module

local M = {}

M.reload_config = function()
  -- recompiles all user lua files
  reload_module("ariel")
  -- reloads the init.lua files to pickup the changes after compilation
  vim.cmd("source " .. vim.env.MY_VIMRC)
  print("config reloaded")
end

M.get_visual_selection = function()
  local s_start = vim.fn.getpos("'<")
  local s_end = vim.fn.getpos("'>")
  local n_lines = math.abs(s_end[2] - s_start[2]) + 1
  local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
  lines[1] = string.sub(lines[1], s_start[3], -1)
  if n_lines == 1 then
    lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3] - s_start[3] + 1)
  else
    lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3])
  end
  return table.concat(lines, "\n")
end

M.create_buffer_keymaper = function(buffer)
  return function(mode, l, r, opts)
    opts = opts or {}
    opts.buffer = buffer
    opts.remap = false
    vim.keymap.set(mode, l, r, opts)
  end
end

M.show_messages = function()
  vim.cmd("redir @a")
  vim.cmd("silent messages")
  vim.cmd("redir END")
  vim.cmd("enew")
  vim.api.nvim_put({ vim.fn.getreg("a") }, "b", true, true)
end

M.delete_comments = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_buf_get_option(bufnr, "ft")
  local lang = require("nvim-treesitter.parsers").ft_to_lang(filetype)
  local ts_utils = require("nvim-treesitter.ts_utils")
  -- example to capture more complex comments: only comments that are included within a function call
  -- named __webpack_require__
  -- local query_text = [[
  --   (call_expression
  --     (identifier) @fn (#eq? @fn "__webpack_require__")
  --     (arguments
  --       (comment) @comment
  --     )
  --   )
  -- ]]
  local query_text = [[
    (comment) @comment
  ]]

  local query = vim.treesitter.query.parse(lang, query_text)
  local parser = vim.treesitter.get_parser()
  local tree = parser:parse()[1] -- test

  for id, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    local start_row, start_col, end_row, end_col = node:range()
    -- add just an empty string in the comment node's range
    vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, { "" })
  end
end

vim.api.nvim_create_user_command("DeleteAllComments", M.delete_comments, {})

return M
