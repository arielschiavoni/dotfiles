local M = {}

M.reload_config = function()
  -- recompiles all user lua files
  require("plenary.reload").reload_module("user")
  -- reloads the init.lua files to pickup the changes after compilation
  dofile(vim.env.MY_VIMRC)
  print("configuration successfully reloaded!")
end

M.buf_map = function(bufnr, mode, lhs, rhs, opts)
  vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts or { silent = true, noremap = true })
end

return M
