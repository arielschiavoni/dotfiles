-- cutom behaviours to apply based on the filetype like auto format on save.
local filetype_attach = setmetatable({
  lua = function(client)
    -- disable extra level of syntax highlighting provided by lsp for lua.
    -- it produces some annoying flashing for some global variables
    client.server_capabilities.semanticTokensProvider = nil
  end,
}, {
  -- __index: Accessed when accessing a non-existing key in the table
  -- use default noop function if the filetype is not defined in the table
  __index = function()
    return function() end
  end,
})

local function setup_lsp_handlers()
  -- Jump directly to the first available definition every time.
  vim.lsp.handlers["textDocument/definition"] = function(_, result)
    if not result or vim.tbl_isempty(result) then
      vim.notify("[LSP] Could not find definition")
      return
    end

    if vim.tbl_islist(result) then
      vim.lsp.util.jump_to_location(result[1], "utf-8")
    else
      vim.lsp.util.jump_to_location(result, "utf-8")
    end
  end
  -- ui tweaks to the lsp popups (rounded border, etc)
  vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })
end

local custom_init = function(client)
  client.config.flags = client.config.flags or {}
  client.config.flags.allow_incremental_sync = true
end

-- adds keymaps to the buffer to trigger lsp actions and configures
-- other language specific features like format on save
local function custom_attach(client, bufnr)
  local map = require("ariel.utils").create_buffer_keymaper(bufnr)
  -- setup keymaps
  map("n", "gD", vim.lsp.buf.declaration, { desc = "Go to declaration" })
  map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
  map("n", "K", vim.lsp.buf.hover, { desc = "Show hover documentation" })
  map("n", "gi", vim.lsp.buf.implementation, { desc = "Go to implementation" })
  map("n", "<C-k>", vim.lsp.buf.signature_help, { desc = "Show signature help" })
  map("n", "gr", vim.lsp.buf.references, { desc = "Go to references" })
  map("n", "<leader>D", vim.lsp.buf.type_definition, { desc = "Go to type definition" })
  map("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
  map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Show code actions" })
  map("n", "<leader>lr", ":LspRestart<CR>", { desc = "Restart LSP server" })
  map("n", "<leader>li", ":LspInfo<CR>", { desc = "Show LSP info" })

  -- Set autocommands conditional on server_capabilities
  -- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentHighlight
  if client.server_capabilities.documentHighlightProvider then
    vim.api.nvim_clear_autocmds({ group = augroup_highlight, buffer = bufnr })
    vim.api.nvim_create_autocmd("CursorHold", {
      buffer = bufnr,
      group = augroup_highlight,
      callback = function()
        vim.lsp.buf.document_highlight()
      end,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = bufnr,
      group = augroup_highlight,
      callback = function()
        vim.lsp.buf.clear_references()
      end,
    })
  end

  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  -- Attach any filetype specific options to the client
  filetype_attach[filetype](client)
end

return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile", "VeryLazy" },
    dependencies = {
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
        underline = false,
        update_in_insert = false,
        virtual_text = {
          source = true,
          spacing = 4,
          prefix = "●",
        },
        severity_sort = true,
        signs = true,
        float = {
          border = "rounded",
          source = "always",
          header = "",
          prefix = "",
        },
      })

      local signs = {
        Error = " ",
        Warn = " ",
        Hint = " ",
        Info = " ",
      }

      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end

      --------------------------------------- LSPs ------------------------------------------
      -- neodev needs to be setup before than the lua lsp
      require("neodev").setup()

      -- setup lsp handlers customisations
      setup_lsp_handlers()

      -- Completion configuration
      local updated_capabilities = vim.lsp.protocol.make_client_capabilities()
      vim.tbl_deep_extend("force", updated_capabilities, require("cmp_nvim_lsp").default_capabilities())

      -- LSP servers
      -- configurations -> https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
      -- before configuring the lsp it needs to be installed using Mason (check ensure_installed Mason config above)
      -- Mason uses a different names for the package that correspond to the lsp. The mapping table
      -- can be found here -> https://github.com/williamboman/mason-lspconfig.nvim/blob/main/doc/server-mapping.md
      -- This setup implies to install the LSP only once with Mason. One could use mason-lspconfig to ensure the LSP is
      -- installed through mason but that implies to load this plugin every time nvim is started which increases startup time (~30ms)
      local servers = {
        lua_ls = {
          settings = {
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
          },
        },
        tsserver = {
          init_options = {
            preferences = {
              disableSuggestions = false,
            },
          },
        },
        yamlls = {
          settings = {
            yaml = {
              -- https://github.com/SchemaStore/schemastore/blob/master/src/api/json/catalog.json
              schemas = require("schemastore").yaml.schemas(),
              validate = false,
            },
          },
        },
        bashls = true,
        html = true,
        eslint = {
          handlers = {
            ["eslint/noLibrary"] = function() end,
          },
        },
        jsonls = {
          settings = {
            json = {
              -- https://github.com/SchemaStore/schemastore/blob/master/src/api/json/catalog.json
              schemas = require("schemastore").json.schemas(),
              validate = true,
            },
          },
        },
        terraformls = true,
        graphql = true,
        gopls = true,
        tailwindcss = {
          filetypes = {
            "html",
            "typescriptreact",
          },
        },
        ocamllsp = {
          get_language_id = function(_, ftype)
            return ftype
          end,
        },
      }

      local setup_server = function(server, config)
        if not config then
          return
        end

        if type(config) ~= "table" then
          config = {}
        end

        config = vim.tbl_deep_extend("force", {
          on_init = custom_init,
          on_attach = custom_attach,
          capabilities = updated_capabilities,
        }, config)

        require("lspconfig")[server].setup(config)
      end

      for server, config in pairs(servers) do
        setup_server(server, config)
      end
    end,
  },
  {
    "j-hui/fidget.nvim",
    opts = {
      -- options
    },
  },
}
