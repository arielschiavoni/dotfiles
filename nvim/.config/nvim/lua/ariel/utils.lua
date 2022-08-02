local reload_module = require("plenary.reload").reload_module

local M = {}

M.reload_config = function()
  -- recompiles all user lua files
  reload_module("ariel")
  -- reloads the init.lua files to pickup the changes after compilation
  vim.cmd("source " .. vim.env.MY_VIMRC)
  print("config reloaded")
end

M.reload_modules = function()
  -- Because TJ gave it to me.  Makes me happpy.  Put it next to his other
  -- awesome things.
  local lua_dirs = vim.fn.glob("./lua/*", 0, 1)
  for _, dir in ipairs(lua_dirs) do
    dir = string.gsub(dir, "./lua/", "")
    reload_module(dir)
  end
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
