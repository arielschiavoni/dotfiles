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
          filter = function(c)
            return c.name == "null-ls" or c.name == "gopls"
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
  local function on_attach(client, bufnr)
    local opts = { buffer = bufnr, remap = false }
    -- setup keymaps
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
    vim.keymap.set("n", "[e", function()
      vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.ERROR })
    end, opts)
    vim.keymap.set("n", "]e", function()
      vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR })
    end, opts)
    vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)
    setup_lsp_format_on_save(client, bufnr, lsp_formatting_augroup)
  end

  return vim.tbl_extend("force", config, {
    capabilities = capabilities,
    on_attach = on_attach,
  })
end

return {
  {
    -- LSP package manager, UI to discover, install and update lsp servers
    -- even though instalation can be done with its UI, the list of LSP should
    -- be also configured in mason-lspconfig -> ensured_installed table.
    "williamboman/mason.nvim",
    build = ":MasonUpdate",
    -- only load this package on demand when its command o keymap is invoqued.
    -- it does not make sense to bound this plugins with lsp configuration which
    -- needs to be loaded when any buffer is opened
    cmd = "Mason",
    keys = {
      { "<leader>ms", ":Mason<CR>", { desc = "open Mason LSP package manager" } },
    },
    config = function()
      require("mason").setup()
    end,
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile", "VeryLazy" },
    dependencies = {
      -- ensure that lsp servers are installed
      "williamboman/mason-lspconfig.nvim",

      -- formatters and linters
      "jose-elias-alvarez/null-ls.nvim",

      -- schema stores needed from some LSPs (json, yaml)
      "b0o/schemastore.nvim",

      -- autcompletion
      "hrsh7th/cmp-nvim-lsp",

      -- for neovim development
      "folke/neodev.nvim",
    },
    config = function()
      -------------------------------------- General config --------------------------------

      -- diagnostics
      vim.diagnostic.config({
        underline = true,
        update_in_insert = false,
        virtual_text = {
          source = true,
          spacing = 4,
          prefix = "●",
        },
        severity_sort = true,
      })

      local signs = {
        Error = " ",
        Warn = " ",
        Hint = " ",
        Info = " ",
      }

      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end

      --------------------------------------- LSPs ------------------------------------------
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "tsserver",
          "graphql",
          "yamlls",
          "jsonls",
          "terraformls",
          "gopls",
        },
      })
      local lspconfig = require("lspconfig")
      local lspconfig_utils = require("lspconfig.util")
      local lsp_formatting_augroup = vim.api.nvim_create_augroup("LspFormatting", {})

      -- the majority of lsps have the same config
      local default_lsp_config = create_default_lsp_config(lspconfig_utils.default_config, lsp_formatting_augroup)

      -- create function to extend default lsp config
      local function create_lsp_config(config)
        return vim.tbl_extend("force", default_lsp_config, config)
      end

      local function create_lua_lsp_settings()
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

      -- lua
      -- neodev needs to be setup before than the lua lsp
      require("neodev").setup()
      lspconfig.lua_ls.setup(create_lsp_config({
        settings = create_lua_lsp_settings(),
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

      ---------------------------------------- Formatters & Linters -----------------------------------
      local null_ls = require("null-ls")

      -- https://github.com/jose-elias-alvarez/null-ls.nvim/blob/main/doc/CONFIG.md#options
      null_ls.setup({
        debug = false,
        root_dir = function(fname)
          -- use the current working directory as the root directory
          -- this is important for the sources like prettier that will be activated
          -- only if the config files are found here!
          return vim.fn.getcwd()
        end,
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
    end,
  },
}
