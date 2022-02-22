local lsp_installer = require("nvim-lsp-installer")

local function buf_map(bufnr, mode, lhs, rhs, opts)
  vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts or { silent = true, noremap = true })
end

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)
  -- See `:help vim.lsp.*` for documentation on any of the below functions
  buf_map(bufnr, "n", "gD", "<cmd>lua vim.lsp.buf.declaration()<CR>")
  buf_map(bufnr, "n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>")
  buf_map(bufnr, "n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>")
  buf_map(bufnr, "n", "gi", "<cmd>lua vim.lsp.buf.implementation()<CR>")
  buf_map(bufnr, "n", "<C-k>", "<cmd>lua vim.lsp.buf.signature_help()<CR>")
  buf_map(bufnr, "n", "<space>D", "<cmd>lua vim.lsp.buf.type_definition()<CR>")
  buf_map(bufnr, "n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>")
  buf_map(bufnr, "n", "<space>ca", "<cmd>lua vim.lsp.buf.code_action()<CR>")
  buf_map(bufnr, "n", "gr", "<cmd>lua vim.lsp.buf.references()<CR>")
  buf_map(bufnr, "n", "<space>e", "<cmd>lua vim.diagnostic.open_float()<CR>")
  buf_map(bufnr, "n", "[d", "<cmd>lua vim.diagnostic.goto_prev()<CR>")
  buf_map(bufnr, "n", "]d", "<cmd>lua vim.diagnostic.goto_next()<CR>")
  buf_map(bufnr, "n", "<space>q", "<cmd>lua vim.diagnostic.setloclist()<CR>")
  buf_map(bufnr, "n", "<space>f", "<cmd>lua vim.lsp.buf.formatting()<CR>")

  if client.name == "tsserver" then
    -- disable tsserver formatting due it is being done by prettier
    client.resolved_capabilities.document_formatting = false
    client.resolved_capabilities.document_range_formatting = false
  end
end

-- Add additional capabilities supported by nvim-cmp
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("cmp_nvim_lsp").update_capabilities(capabilities)

local lsp_settings = {}

lsp_settings["sumneko_lua"] = {
  Lua = {
    diagnostics = {
      globals = { "vim", "use" },
    },
    workspace = {
      -- Make the server aware of Neovim runtime files
      library = { [vim.fn.expand("$VIMRUNTIME/lua")] = true, [vim.fn.expand("$VIMRUNTIME/lua/vim/lsp")] = true },
    },
  },
}

-- Register a handler that will be called for all installed servers.
-- Alternatively, you may also register handlers on specific server instances instead (see example below).
lsp_installer.on_server_ready(function(server)
  local opts = {
    settings = lsp_settings[server.name],
    on_attach = on_attach,
    capabilities = capabilities,
    flags = {
      debounce_text_changes = 150,
    },
  }
  -- This setup() function is exactly the same as lspconfig's setup function.
  -- Refer to https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
  server:setup(opts)
end)
