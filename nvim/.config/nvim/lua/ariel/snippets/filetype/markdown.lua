local ls = require("luasnip")

local s = ls.s
local i = ls.insert_node
local t = ls.text_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

ls.add_snippets("markdown", {
  s({ trig = "t", name = "task" }, fmt("- [{}] {}", { c(2, { t(" "), t("-"), t("x") }), i(1, "task") })),
  s({ trig = "l", name = "link" }, fmt("[{}]({})", { i(1, "text"), i(2, "link") })),
})
