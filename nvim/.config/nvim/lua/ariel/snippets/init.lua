local ls = require("luasnip")

local s = ls.s
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node

-- make sure the current snippets are cleaned up before registering them (needed for reloading)
ls.cleanup()

-- https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md
-- https://alpha2phi.medium.com/neovim-for-beginners-snippets-using-lua-11e46c4d417c
-- `all` key means for all filetypes.
-- Shared between all filetypes. Has lower priority than a particular ft
ls.add_snippets("all", {
  s({ trig = "trigger", name = "demo snippet" }, {
    t({ "demo snippet, plese enter " }),
    i(1, "your name"),
    t({ "", "then press <c-k> to jump to the " }),
    i(2, "next snippet position"),
    t({ "", "then press <c-j> to jump to the previous snippet possition", "" }),
    i(0, "end"),
  }),
  s(
    {
      trig = "cd",
      name = "current date",
    },
    f(function()
      return os.date("%d/%m/%Y")
    end)
  ),
})

-- load all snippet files
for _, ft_path in ipairs(vim.api.nvim_get_runtime_file("lua/ariel/snippets/filetype/*.lua", true)) do
  loadfile(ft_path)()
end

print("snippets loaded")
