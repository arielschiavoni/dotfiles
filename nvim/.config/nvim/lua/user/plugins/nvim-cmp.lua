local has_words_before = function()
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local cmp = require("cmp")
local luasnip = require("luasnip")

local function tab(fallback)
  if cmp.visible() then
    cmp.select_next_item()
  elseif luasnip.expand_or_jumpable() then
    luasnip.expand_or_jump()
  elseif has_words_before() then
    cmp.complete()
  else
    -- F("<Tab>")
    fallback()
  end
end

local function shtab(fallback)
  if cmp.visible() then
    cmp.select_prev_item()
  elseif luasnip.jumpable(-1) then
    luasnip.jump(-1)
  else
    -- F('<S-Tab>')
    fallback()
  end
end

local function enterit(fallback)
  if cmp.visible() and cmp.get_selected_entry() then
    cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = false })
  else
    -- F("<CR>")
    fallback()
  end
end

cmp.setup({
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = {
    ["<C-d>"] = cmp.mapping.scroll_docs(-4),
    ["<C-f>"] = cmp.mapping.scroll_docs(4),
    ["<Tab>"] = cmp.mapping(tab, { "i", "s", "c" }),
    ["<S-Tab>"] = cmp.mapping(shtab, { "i", "s", "c" }),
    ["<CR>"] = cmp.mapping(enterit, { "i", "s" }),
  },
  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "luasnip" },
    { name = "fuzzy_buffer" },
    { name = "fuzzy_path" },
    { name = "emoji" },
    { name = "nvim_lua" },
  }),
})

for _, cmd_type in ipairs({ ":", "/", "?", "@" }) do
  cmp.setup.cmdline(cmd_type, {
    sources = {
      { name = "cmdline" },
      { name = "cmdline_history" },
      { name = "fuzzy_buffer" },
      { name = "fuzzy_path" },
    },
  })
end
