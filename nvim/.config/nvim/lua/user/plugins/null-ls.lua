local null_ls = require("null-ls")
local builtins = null_ls.builtins
local formatting = builtins.formatting
local diagnostics = builtins.diagnostics

null_ls.setup({
  sources = {
    formatting.stylua.with({
      args = { "--indent-width", "2", "--indent-type", "Spaces", "-" },
    }),
    formatting.prettier,
    diagnostics.eslint,
  },
})
