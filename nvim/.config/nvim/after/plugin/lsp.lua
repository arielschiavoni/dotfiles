-- mason will only make sure that Neovim can find your installed servers,
-- it does not set up any servers for you automatically. You will have to set up your servers yourself (for example via lspconfig).
-- In order for mason to register the necessary hooks at the right moment,
-- make sure you call the require("mason").setup() function before you set up any servers!
require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = { "sumneko_lua", "tsserver", "graphql", "yamlls", "jsonls", "terraformls", "gopls" },
})

-- if the lsp client supports formatting, setup an autocommand that will
-- format the buffer when the "BufWritePre" event occurs ("on save")
local function setup_lsp_format_on_save(client, bufnr, lsp_formatting_augroup)
  if client.supports_method("textDocument/formatting") then
    vim.api.nvim_clear_autocmds({ group = lsp_formatting_augroup, buffer = bufnr })
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = lsp_formatting_augroup,
      buffer = bufnr,
      callback = function()
        -- Format buffer synchronously (recommended)
        -- https://github.com/jose-elias-alvarez/null-ls.nvim/wiki/Formatting-on-save#sync-formatting
        vim.lsp.buf.format({
          -- only format the buffer if the client name is "null-ls" this is required
          -- because other lsp clients (tsserver, lua, json, yml, etc) have formatting
          -- capabilities that we don't want to use because null-ls takes care of formatting
          -- using prettier, stylelua, etc.
          filter = function(client)
            return client.name == "null-ls" or client.name == "gopls"
          end,
          bufnr = bufnr,
        })
      end,
    })
  end
end

-- creates default configuration for all LSP clients
-- autocomplete: make cmp lsp capabilities available for all LSPs
-- on_attach: setup keymaps and auto formatting for all LSPs
local function create_default_lsp_config(config, lsp_formatting_augroup)
  -- Add additional capabilities supported by nvim-cmp
  local capabilities = require("cmp_nvim_lsp").default_capabilities()
  local nnoremap = require("ariel.keymap").nnoremap
  local telescope_builtin = require("telescope.builtin")
  local function on_attach(client, bufnr)
    -- setup keymaps
    nnoremap("gD", vim.lsp.buf.declaration)
    nnoremap("gd", vim.lsp.buf.definition)
    nnoremap("K", vim.lsp.buf.hover)
    nnoremap("gi", vim.lsp.buf.implementation)
    nnoremap("<C-k>", vim.lsp.buf.signature_help)
    nnoremap("gr", vim.lsp.buf.references)
    nnoremap("<leader>D", vim.lsp.buf.type_definition)
    nnoremap("<leader>rn", vim.lsp.buf.rename)
    nnoremap("<leader>ca", vim.lsp.buf.code_action)
    nnoremap("<leader>dl", telescope_builtin.diagnostics)
    nnoremap("[d", vim.diagnostic.goto_prev)
    nnoremap("]d", vim.diagnostic.goto_next)
    nnoremap("<leader>q", vim.diagnostic.setloclist)

    setup_lsp_format_on_save(client, bufnr, lsp_formatting_augroup)
  end

  return vim.tbl_extend("force", config, {
    capabilities = capabilities,
    on_attach = on_attach,
  })
end

local lspconfig_utils = require("lspconfig.util")
local lsp_formatting_augroup = vim.api.nvim_create_augroup("LspFormatting", {})
local default_lsp_config = create_default_lsp_config(lspconfig_utils.default_config, lsp_formatting_augroup)

local function create_lsp_config(config)
  return vim.tbl_extend("force", default_lsp_config, config)
end

-- ################### LSPs #############################
local lspconfig = require("lspconfig")

-- null-ls (formatting and diagnostic tools like prettier, eslint, etc)
local null_ls = require("null-ls")

null_ls.setup({
  debug = false,
  sources = {
    null_ls.builtins.formatting.stylua.with({
      args = { "--indent-width", "2", "--indent-type", "Spaces", "-" },
    }),
    null_ls.builtins.formatting.prettierd.with({
      timeout = 20000,
      condition = function(utils)
        return utils.root_has_file({ "prettier.config.js", ".prettierrc", ".prettierignore" })
      end,
    }),
    null_ls.builtins.diagnostics.eslint_d.with({
      timeout = 20000,
      condition = function(utils)
        return utils.root_has_file({ ".eslintrc.js", ".eslintrc.json", ".eslintrc" })
      end,
    }),
    null_ls.builtins.code_actions.eslint_d.with({
      timeout = 20000,
      condition = function(utils)
        return utils.root_has_file({ ".eslintrc.js", ".eslintrc.json", ".eslintrc" })
      end,
    }),
  },
  on_attach = function(client, bufnr)
    setup_lsp_format_on_save(client, bufnr, lsp_formatting_augroup)
  end,
})

-- lua
local function create_sumneko_lua_settings()
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
        library = vim.api.nvim_get_runtime_file("", true),
        checkThirdParty = false,
      },
      -- Do not send telemetry data containing a randomized but unique identifier
      telemetry = { enable = false },
    },
  }
end

lspconfig.sumneko_lua.setup(create_lsp_config({
  settings = create_sumneko_lua_settings(),
}))

-- typescript
lspconfig.tsserver.setup(default_lsp_config)

-- yaml (autocomplete based on schema stores)

-- https://github.com/SchemaStore/schemastore/blob/master/src/api/json/catalog.json
local schemas = require("schemastore").json.schemas

lspconfig.yamlls.setup(create_lsp_config({
  settings = {
    yaml = {
      schemas = schemas({
        select = {
          "GitHub Action",
          "GitHub Workflow",
          "GraphQL Code Generator",
          -- "Serverless Framework Configuration",
        },
      }),
      validate = { enable = true },
    },
  },
}))

-- json (autocomplete based on schema stores)

lspconfig.jsonls.setup(create_lsp_config({
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
}))

-- terraform
lspconfig.terraformls.setup(default_lsp_config)

-- graphql
require("lspconfig").graphql.setup(default_lsp_config)

-- go
require("lspconfig").gopls.setup(default_lsp_config)

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
  signs = true,
  underline = false,
  virtual_text = true,
  show_diagnostic_autocmds = { "InsertLeave", "TextChanged" },
  diagnostic_delay = 500,
})
