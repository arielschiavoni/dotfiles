local M = {}

M.reload_config = function()
  -- recompiles all user lua files
  require("plenary.reload").reload_module("user")
  -- reloads the init.lua files to pickup the changes after compilation
  dofile(vim.env.MY_VIMRC)
  print(" ~> user config reloaded!")
end

M.buf_map = function(bufnr, mode, lhs, rhs, custom_opts)
  local opts = { silent = true, noremap = true }

  -- merge tables
  for k, v in pairs(custom_opts or {}) do
    opts[k] = v
  end

  vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
end

return M
