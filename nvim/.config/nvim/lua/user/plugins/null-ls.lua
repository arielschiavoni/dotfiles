local null_ls = require("null-ls")
local builtins = null_ls.builtins
local formatting = builtins.formatting
local diagnostics = builtins.diagnostics

null_ls.setup({
	sources = {
		formatting.prettier,
		diagnostics.eslint,
	},
})
