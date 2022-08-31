require("nvim-lsp-installer").setup({})
local nnoremap = require("ariel.keymap").nnoremap
local lspconfig = require("lspconfig")

-- Add additional capabilities supported by nvim-cmp
local capabilities = vim.lsp.protocol.make_client_capabilities()
local capabilities_with_cmp = require("cmp_nvim_lsp").update_capabilities(capabilities)
local lspconfig_utils = require("lspconfig.util")

-- make cmp lsp capabilities available for all LSPs
-- this avoids having to pass capabilities on every LSP config
lspconfig_utils.default_config = vim.tbl_extend("force", lspconfig_utils.default_config, {
  capabilities = capabilities_with_cmp,
})

local function on_attach()
  nnoremap("gD", vim.lsp.buf.declaration)
  nnoremap("gd", vim.lsp.buf.definition)
  nnoremap("K", vim.lsp.buf.hover)
  nnoremap("gi", vim.lsp.buf.implementation)
  nnoremap("<C-k>", vim.lsp.buf.signature_help)
  nnoremap("gr", vim.lsp.buf.references)
  nnoremap("[d", vim.diagnostic.goto_prev)
  nnoremap("]d", vim.diagnostic.goto_next)
  nnoremap("<leader>D", vim.lsp.buf.type_definition)
  nnoremap("<leader>rn", vim.lsp.buf.rename)
  nnoremap("<leader>ca", vim.lsp.buf.code_action)
  nnoremap("<leader>q", vim.diagnostic.setloclist)
end

local function create_sumneko_lua_settings()
  local function create_library()
    local library_paths = {
      -- add neovim runtime
      "$VIMRUNTIME/lua",
      "$VIMRUNTIME/lua/vim/lsp",
      -- add plugins
      -- "~/.local/share/nvim/site/pack/packer/opt/*",
      "~/.local/share/nvim/site/pack/packer/start/*",
      -- add my config
      "~/.config/nvim",
    }

    local library = {}

    for _, library_path in ipairs(library_paths) do
      -- expand will return an array with all path that matches glob expressions like *
      for _, path in pairs(vim.fn.expand(library_path, false, true)) do
        -- for all expanded paths get the real path and include it in the library table
        path = vim.loop.fs_realpath(path)
        library[path] = true
      end
    end

    return library
  end

  return {
    Lua = {
      runtime = {
        -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
        version = "LuaJIT",
        -- Setup your lua path
        path = vim.split(package.path, ";"),
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = { "vim" },
      },
      workspace = {
        -- Make the server aware of Neovim runtime files
        library = create_library(),
        maxPreload = 2000,
        preloadFileSize = 50000,
      },
      -- Do not send telemetry data containing a randomized but unique identifier
      telemetry = { enable = false },
    },
  }
end

lspconfig.sumneko_lua.setup({
  on_attach = function(client)
    on_attach()
    -- disable sumneko_lua formatting due it is being done by stylua (null_ls)
    client.resolved_capabilities.document_formatting = false
    client.resolved_capabilities.document_range_formatting = false
  end,
  settings = create_sumneko_lua_settings(),
})

lspconfig.tsserver.setup({
  on_attach = function(client)
    on_attach()
    -- disable tsserver formatting due it is being done by prettier (null_ls)
    client.resolved_capabilities.document_formatting = false
    client.resolved_capabilities.document_range_formatting = false
  end,
})

-- https://github.com/SchemaStore/schemastore/blob/master/src/api/json/catalog.json
local schemas = require("schemastore").json.schemas

lspconfig.yamlls.setup({
  on_attach = on_attach,
  settings = {
    yaml = {
      schemas = vim.list_extend(
        {
          {
            name = "Apollo Router",
            description = "YAML Schema for the Apollo Router configuration",
            fileMatch = { "router.yml", "router.yaml" },
            url = "https://raw.githubusercontent.com/arielschiavoni/dotfiles/master/nvim/.config/nvim/after/plugin/apollo-router.json",
          },
        },
        schemas({
          select = {
            "GitHub Action",
            "GitHub Workflow",
            "GraphQL Code Generator",
            -- "Serverless Framework Configuration",
          },
        })
      ),
      validate = { enable = true },
    },
  },
})

lspconfig.jsonls.setup({
  on_attach = function(client)
    on_attach()
    -- disable tsserver formatting due it is being done by prettier (null_ls)
    client.resolved_capabilities.document_formatting = false
    client.resolved_capabilities.document_range_formatting = false
  end,
  settings = {
    json = {
      schemas = schemas({
        select = {
          ".eslintrc",
          "package.json",
          "tsconfig.json",
          "Renovate",
          "prettierrc.json",
          "rustfmt",
          "semantic-release",
          "size-limit configuration",
          "AWS CDK cdk.json",
          "cypress.json",
          "Vercel",
          "dependabot.json",
          "dependabot-v2.json",
        },
      }),
      validate = { enable = true },
    },
  },
})

lspconfig.terraformls.setup({
  on_attach = on_attach,
})

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
  signs = true,
  underline = false,
  virtual_text = true,
  show_diagnostic_autocmds = { "InsertLeave", "TextChanged" },
  diagnostic_delay = 500,
})
