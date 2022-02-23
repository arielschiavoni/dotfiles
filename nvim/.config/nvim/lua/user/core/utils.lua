local M = {}

M.reload_config = function()
  for name, _ in pairs(package.loaded) do
    if name:match("^user") then
      vim.cmd(":PackerCompile")
      package.loaded[name] = nil
    end
  end

  dofile(vim.env.MY_VIMRC)

  print(vim.env.MY_VIMRC .. " was reloaded")
end

return M
