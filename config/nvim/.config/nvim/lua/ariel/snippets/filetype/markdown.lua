local ls = require("luasnip")

local s = ls.s
local i = ls.insert_node
local t = ls.text_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

ls.add_snippets("markdown", {
  s({ trig = "t", name = "task" }, fmt("- [{}] {}", { c(2, { t(" "), t("-"), t("x") }), i(1, "task") })),
  s({ trig = "l", name = "link" }, fmt("[{}]({})", { i(1, "text"), i(2, "link") })),
  s({ trig = "cb", name = "code block" }, {
    t({ "```" }), -- Start the code block
    i(1, "language"), -- Placeholder for the optional language identifier
    t({ "", "" }), -- New line to start the actual code
    i(2, "code"), -- Placeholder for the user's code
    t({ "", "```" }), -- Ending the code block
  }),
})
