local M = {}

M.reload_config = function()
  -- recompiles all user lua files
  require("plenary.reload").reload_module("ariel")
  -- reloads the init.lua files to pickup the changes after compilation
  dofile(vim.env.MY_VIMRC)
  print("config reloaded")
end

M.toggle_background = function()
  local current_background = vim.api.nvim_get_option_value("background", {})
  local new_background = "dark"

  if current_background == "dark" then
    new_background = "light"
  end

  vim.api.nvim_set_option_value("background", new_background, {})
end

return M
