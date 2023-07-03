local augroup_format = vim.api.nvim_create_augroup("custom-lsp-format", { clear = true })
local augroup_highlight = vim.api.nvim_create_augroup("custom-lsp-references", { clear = true })

local function autocmd_format()
  -- 0 is the current buffer
  vim.api.nvim_clear_autocmds({ buffer = 0, group = augroup_format })
  vim.api.nvim_create_autocmd("BufWritePre", {
    buffer = 0,
    group = augroup_format,
    callback = function()
      vim.lsp.buf.format({ async = false })
    end,
  })
end

local function disable_lsp_formatting(client)
  client.resolved_capabilities.document_formatting = false
  client.resolved_capabilities.document_range_formatting = false
end

-- cutom behaviours to apply based on the filetype like auto format on save.
local filetype_attach = setmetatable({
  ocaml = function()
    autocmd_format()
  end,

  go = function()
    autocmd_format()
  end,

  lua = function(client)
    -- disable extra level of syntax highlighting provided by lsp for lua.
    -- it produces some annoying flashing for some global variables
    client.server_capabilities.semanticTokensProvider = nil
    -- formatting is done by null_ls -> stylua
    disable_lsp_formatting(client)
  end,

  typescript = function(client)
    -- formatting is done by null_ls -> prettier
    disable_lsp_formatting(client)
  end,

  javascript = function(client)
    -- formatting is done by null_ls -> prettier
    disable_lsp_formatting(client)
  end,

  html = function(client)
    -- formatting is done by null_ls -> prettier
    disable_lsp_formatting(client)
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
      { "<leader>ms", ":Mason<CR>", desc = "open Mason LSP package manager" },
    },
    opts = {
      ensure_installed = {
        "eslint_d",
        "prettierd",
        "js-debug-adapter",
      },
    },
    ---@param opts MasonSettings | {ensure_installed: string[]}
    config = function(_, opts)
      require("mason").setup(opts)
      local mr = require("mason-registry")
      for _, tool in ipairs(opts.ensure_installed) do
        local p = mr.get_package(tool)
        if not p:is_installed() then
          p:install()
        end
      end
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

      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "tsserver",
          "graphql",
          "yamlls",
          "jsonls",
          "tailwindcss",
          "terraformls",
          "gopls",
          "ocamllsp",
          "bashls",
          "html",
        },
      })

      -- setup lsp handlers customisations
      setup_lsp_handlers()

      -- Completion configuration
      local updated_capabilities = vim.lsp.protocol.make_client_capabilities()
      vim.tbl_deep_extend("force", updated_capabilities, require("cmp_nvim_lsp").default_capabilities())

      -- LSP servers
      -- configurations -> https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
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
        tsserver = true,
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
        tailwindcss = true,
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

      local null_ls = require("null-ls")
      null_ls.setup({
        -- https://github.com/jose-elias-alvarez/null-ls.nvim/blob/main/doc/CONFIG.md#options
        debug = false,
        root_dir = function()
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
          null_ls.builtins.formatting.eslint_d.with({
            timeout = 20000,
            condition = function(utils)
              return utils.root_has_file({ ".eslintrc.js", ".eslintrc.json", ".eslintrc" })
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
        on_attach = function()
          -- setup autocmd to format on buffer save (required by stylua, prettier, etc)
          autocmd_format()
        end,
      })
    end,
  },
}
