local utils = {}
local ls = require("luasnip")

function utils.remap(mode, lhs, rhs, opts)
  local options = { noremap = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  vim.api.nvim_set_keymap(mode, lhs, rhs, options)
end

function utils.reload_config()
  for name, _ in pairs(package.loaded) do
    if name:match("^user") then
      package.loaded[name] = nil
    end
  end

  dofile(vim.env.MY_VIMRC)

  --print(vim.env.MY_VIMRC .. ' was reloaded')
end

-- TODO: remove when upgrade to neovim 0.7 is done
-- https://github.com/tjdevries/config_manager/blob/master/xdg_config/nvim/after/plugin/luasnip.lua#L326
-- this will expand the current item or jump to the next item within the snippet.
function utils.expand_snippet()
  if ls.expand_or_jumpable() then
    ls.expand_or_jump()
  end
end

-- this always moves to the previous item within the snippet
function utils.jump_backwards_snippet()
  if ls.jumpable(-1) then
    ls.jump(-1)
  end
end

return utils
