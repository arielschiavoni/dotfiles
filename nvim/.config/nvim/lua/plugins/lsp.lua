local augroup_highlight = vim.api.nvim_create_augroup("custom-lsp-references", { clear = true })

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
    -- setup autocommand to automatically highlight the word under the cursor. It helps to visualize the references of a variable or function
    -- under the cursor
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
end

return {
  {
    "neovim/nvim-lspconfig",
    event = { "VeryLazy" },
    dependencies = {
      -- schema stores needed from some LSPs (json, yaml)
      "b0o/schemastore.nvim",
      -- autcompletion
      "saghen/blink.cmp",
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

      -- ui tweaks to the lsp popups (rounded border, etc)
      vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
      vim.lsp.handlers["textDocument/signatureHelp"] =
        vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })

      --------------------------------------- LSPs ------------------------------------------
      -- LSP servers
      -- configurations -> https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
      -- before configuring the lsp it needs to be installed using Mason
      -- Mason uses a different name for the package that correspond to the lsp. The mapping table
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
        ts_ls = {
          init_options = {
            preferences = {
              disableSuggestions = false,
            },
          },
        },
        yamlls = {
          settings = {
            yaml = {
              -- https://github.com/b0o/SchemaStore.nvim?tab=readme-ov-file#usage
              schemaStore = {
                -- You must disable built-in schemaStore support if you want to use
                -- this plugin and its advanced options like `ignore`.
                enable = false,
                -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
                url = "",
              },
              schemas = require("schemastore").yaml.schemas(),
            },
          },
        },
        bashls = true,
        html = true,
        -- conficts with blink.nvim
        -- https://github.com/Saghen/blink.cmp/issues/825
        -- htmx = true,
        eslint = {
          settings = {
            -- helps eslint find the eslintrc when it's placed in a subfolder instead of the cwd root
            workingDirectories = { mode = "auto" },
            -- allows to use flat config format
            useFlatConfig = true,
          },
        },
        jsonls = {
          settings = {
            json = {
              -- https://github.com/b0o/SchemaStore.nvim?tab=readme-ov-file#usage
              schemas = require("schemastore").json.schemas(),
              validate = { enable = true },
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
        nil_ls = {
          formatting = {
            command = { "nixfmt" },
          },
        },
      }

      local capabilities = require("blink.cmp").get_lsp_capabilities()

      local setup_server = function(server, config)
        if not config then
          return
        end

        if type(config) ~= "table" then
          config = {}
        end

        config = vim.tbl_deep_extend("force", {
          on_attach = custom_attach,
          capabilities = capabilities,
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
    event = { "VeryLazy" },
    opts = {
      -- options
    },
  },
}
