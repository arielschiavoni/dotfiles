local augroup_highlight = vim.api.nvim_create_augroup("custom-lsp-references", { clear = true })

-- adds keymaps to the buffer to trigger lsp actions and configures
-- other language specific features like format on save
local function custom_attach(client, bufnr)
  local map = require("ariel.utils").create_buffer_keymaper(bufnr)
  -- setup keymaps
  map("n", "K", function()
    vim.lsp.buf.hover({ border = "single", max_height = 25 })
  end, { desc = "Show hover documentation" })
  map("n", "<C-k>", vim.lsp.buf.signature_help, { desc = "Show signature help" })
  map("n", "<leader>D", vim.lsp.buf.type_definition, { desc = "Go to type definition" })
  map("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
  map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Show code actions" })
  map("n", "<leader>lr", ":LspRestart<CR>", { desc = "Restart LSP server" })
  map("n", "<leader>li", ":LspInfo<CR>", { desc = "Show LSP info" })

  if client.name == "ruff" then
    -- Disable hover in favor of Pyright
    client.server_capabilities.hoverProvider = false
  end

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
      virtual_text = false,
      virtual_lines = false,
      severity_sort = true,
      float = {
        source = true,
        header = "Diagnostics:",
        prefix = " ",
        border = "single",
      },
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = " ",
          [vim.diagnostic.severity.WARN] = " ",
          [vim.diagnostic.severity.HINT] = " ",
          [vim.diagnostic.severity.INFO] = " ",
        },
      },
    })

    vim.api.nvim_create_autocmd("CursorHold", {
      pattern = "*",
      callback = function()
        if #vim.diagnostic.get(0) == 0 then
          return
        end

        if not vim.b.diagnostics_pos then
          vim.b.diagnostics_pos = { nil, nil }
        end

        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        if cursor_pos[1] ~= vim.b.diagnostics_pos[1] or cursor_pos[2] ~= vim.b.diagnostics_pos[2] then
          vim.diagnostic.open_float()
        end

        vim.b.diagnostics_pos = cursor_pos
      end,
    })

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
      -- installed with homebrew because mason still does not include it
      -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#fish_lsp
      fish_lsp = true,
      ruff = {
        init_options = {
          settings = {
            -- disable as it removes unused imports automatically
            organizeImports = false,
          },
        },
      },
      pyright = {
        settings = {
          pyright = {
            -- Using Ruff's import organizer
            disableOrganizeImports = true,
          },
          python = {
            analysis = {
              -- Ignore all files for analysis to exclusively use Ruff for linting
              ignore = { "*" },
            },
          },
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

      vim.lsp.config(server, config)
      vim.lsp.enable(server)
    end

    for server, config in pairs(servers) do
      setup_server(server, config)
    end
  end,
}
