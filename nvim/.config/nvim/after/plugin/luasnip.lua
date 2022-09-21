local ls = require("luasnip")
local types = require("luasnip.util.types")

ls.config.set_config({
  -- This tells LuaSnip to remember to keep around the last snippet.
  -- You can jump back into it even if you move outside of the selection
  history = true,

  -- This one is cool cause if you have dynamic snippets, it updates as you type!
  updateevents = "TextChanged,TextChangedI",

  -- Autosnippets:
  enable_autosnippets = true,

  -- Crazy highlights!!
  -- #vid3
  -- ext_opts = nil,
  ext_opts = {
    [types.choiceNode] = {
      active = {
        virt_text = { { "<-", "Error" } },
      },
    },
  },
})

-- TODO create some useful LUA snippet
-- https://sbulav.github.io/vim/neovim-setting-up-luasnip/
-- https://github.com/nuxshed/dotfiles/blob/main/config/nvim/lua/plugins/snippets.lua
-- https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md
-- https://www.youtube.com/watch?v=KtQZRAkgLqo
-- local s = ls.snippet
-- local sn = ls.snippet_node
-- local isn = ls.indent_snippet_node
-- local t = ls.text_node
-- local i = ls.insert_node
-- local f = ls.function_node
-- local c = ls.choice_node
-- local d = ls.dynamic_node
-- local r = ls.restore_node
-- local fmt = require("luasnip.extras.fmt").fmt

-- TODO
-- Create a telescope view with all snippets available for the current buffer filetype!
-- It could be similar to the keymap view (telescope_builtin.keymaps)
-- when the snippet is selected it is inserted in the current buffer possition!
-- lua print(vim.inspect(require('luasnip.loaders._caches')))
-- lua print(vim.inspect(require'luasnip'.available()))

-- Load snippets from JSON files (VSCode syntax)
-- https://github.com/L3MON4D3/LuaSnip#add-snippets
require("luasnip.loaders.from_vscode").lazy_load()
