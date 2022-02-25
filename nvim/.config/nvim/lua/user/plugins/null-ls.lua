local null_ls = require("null-ls")
local builtins = null_ls.builtins
local formatting = builtins.formatting
local diagnostics = builtins.diagnostics
local code_actions = builtins.code_actions

null_ls.setup({
  debug = false,
  sources = {
    formatting.stylua.with({
      args = { "--indent-width", "2", "--indent-type", "Spaces", "-" },
    }),
    formatting.prettierd,
    diagnostics.eslint_d.with({
      timeout = 20000,
    }),
    code_actions.eslint_d.with({ timeout = 20000 }),
  },
  on_attach = function(client)
    if client.resolved_capabilities.document_formatting then
      vim.cmd("autocmd BufWritePre <buffer> lua vim.lsp.buf.formatting_sync()")
    end
  end,
})
