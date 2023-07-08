local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local d = ls.dynamic_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

local require_var = function(args, _)
  local text = args[1][1] or ""
  local split = vim.split(text, ".", { plain = true })

  local options = {}
  for len = 0, #split - 1 do
    table.insert(options, t(table.concat(vim.list_slice(split, #split - len, #split), "_")))
  end

  return sn(nil, {
    c(1, options),
  })
end

ls.add_snippets("lua", {
  s({ trig = "ignore", name = "ignore stylua formatting" }, { t("--stylua: ignore") }),
  s({ trig = "f", name = "anonymous function" }, fmt("function({})\n  {}\nend", { i(1), i(0) })),
  s({ trig = "lf", name = "local function" }, fmt("local function {}({})\n  {}\nend", { i(1), i(2), i(0) })),
  s({ trig = "for", name = "for loop" }, {
    t("for "),
    i(1, "k, v"),
    t(" in "),
    i(2, "ipairs()"),
    t({ "do", "  " }),
    i(0),
    t({ "", "" }),
    t("end"),
  }),
  s(
    {
      trig = "req",
      name = "require",
    },
    fmt([[local {} = require("{}")]], {
      d(2, require_var, { 1 }),
      i(1),
    })
  ),
  s(
    {
      trig = "treq",
      name = "telescope require",
    },
    -- telescope require
    fmt([[local {} = require("telescope.{}")]], {
      d(2, require_var, { 1 }),
      i(1),
    })
  ),
})
