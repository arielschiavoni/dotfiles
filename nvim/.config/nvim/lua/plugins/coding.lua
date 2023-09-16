return {
  -- autocompletion
  {
    "hrsh7th/nvim-cmp",
    version = false, -- last release is way too old
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-emoji",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-nvim-lua",
      "dmitmel/cmp-cmdline-history",
      "saadparwaiz1/cmp_luasnip",
      "hrsh7th/cmp-nvim-lsp-signature-help",
      "onsails/lspkind.nvim",
    },
    opts = function()
      local cmp = require("cmp")
      local max_item_count = 10

      cmp.setup.cmdline("/", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "buffer", max_item_count = max_item_count },
        }),
      })

      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path", max_item_count = max_item_count },
          { name = "cmdline_history", max_item_count = max_item_count },
          { name = "cmdline", max_item_count = max_item_count },
        }),
      })

      return {
        completion = {
          completeopt = "menu,menuone,noinsert",
        },
        snippet = {
          expand = function(args)
            require("luasnip").lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
          ["<S-CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = true,
          }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
        }),
        formatting = {
          format = require("lspkind").cmp_format({
            with_text = true,
            menu = {
              buffer = "[buf]",
              nvim_lsp = "[LSP]",
              nvim_lsp_signature_help = "[LSP-sh]",
              nvim_lua = "[lua]",
              path = "[path]",
              cmdline = "[cmd]",
              cmdline_history = "[history]",
              luasnip = "[snip]",
              neorg = "[neorg]",
              emoji = "[emoji]",
            },
          }),
        },
        sources = cmp.config.sources({
          { name = "luasnip", max_item_count = max_item_count },
          { name = "nvim_lua", max_item_count = max_item_count },
          { name = "nvim_lsp", max_item_count = max_item_count },
          { name = "nvim_lsp_signature_help", max_item_count = max_item_count },
          { name = "neorg", max_item_count = max_item_count },
        }, {
          { name = "path", max_item_count = max_item_count },
          { name = "emoji", max_item_count = max_item_count },
          { name = "buffer", max_item_count = max_item_count },
        }),
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        experimental = {
          ghost_text = {
            hl_group = "LspCodeLens",
          },
        },
      }
    end,
  },
  -- comments
  {
    "echasnovski/mini.comment",
    dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      hooks = {
        pre = function()
          require("ts_context_commentstring.internal").update_commentstring({})
        end,
      },
    },
    config = function(_, opts)
      require("mini.comment").setup(opts)
    end,
  },
  {
    "stevearc/conform.nvim",
    event = "VeryLazy",
    config = function()
      local prettier_filetypes = {
        "css",
        "graphql",
        "html",
        "javascript",
        "javascriptreact",
        "json",
        "markdown",
        "typescript",
        "typescriptreact",
        "yaml",
      }

      local formatters_by_ft = {
        lua = { "stylua" },
        ocaml = { "ocamlformat" },
        go = { "gofmt" },
        ["*"] = { "trim_whitespace" },
      }

      for _, prettier_filetype in ipairs(prettier_filetypes) do
        -- Use a sub-list to run only the first available formatter
        -- TODO: use prettierd by default as soon as https://github.com/fsouza/prettierd/issues/611 is fixed
        formatters_by_ft[prettier_filetype] = { { "prettier", "prettierd" } }
      end

      require("conform").setup({
        -- If this is set, Conform will run the formatter on save.
        -- It will pass the table to conform.format().
        format_on_save = {
          -- These options will be passed to conform.format()
          timeout_ms = 500,
          lsp_fallback = true,
        },
        -- If this is set, Conform will run the formatter asynchronously after save.
        -- It will pass the table to conform.format().
        format_after_save = {
          lsp_fallback = true,
        },
        formatters_by_ft = formatters_by_ft,
      })
    end,
  },
  -- others
  {
    -- todo replace with echasnovski/mini.surround
    "tpope/vim-surround",
    event = "VeryLazy",
  },
  -- add useful keymaps (add spaces before or after line)
  {
    "tpope/vim-unimpaired",
    event = "VeryLazy",
  },
  -- awesome replacement and case utils (snake, camel, etc)
  {
    "tpope/vim-abolish",
    event = "VeryLazy",
  },
  {
    "mbbill/undotree",
    event = "VeryLazy",
    config = function()
      vim.o.undofile = true
      vim.g.undotree_SplitWidth = 50
      vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle, { desc = "toggle undotree" })
    end,
  },
  {
    "norcalli/nvim-colorizer.lua",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("colorizer").setup()
    end,
  },
  {
    "stevearc/oil.nvim",
    event = "VeryLazy",
    keys = {
      {
        "-",
        function()
          require("oil").open()
        end,
        desc = "open parent directory",
      },
    },
    opts = {
      columns = {
        "icon",
        -- "permissions",
        -- "size",
        -- "mtime",
      },
      -- https://github.com/stevearc/oil.nvim#options
      view_options = {
        -- Show files and directories that start with "."
        show_hidden = true,
      },
      keymaps = {
        -- deactivate undesired keymaps
        ["<C-s>"] = false,
        ["<C-h>"] = false,
        ["<C-t>"] = false,
        ["<C-p>"] = false,
        ["gs"] = false,
      },
    },
    config = function(_, opts)
      require("oil").setup(opts)
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      plugins = { spelling = true },
      defaults = {
        mode = { "n", "v" },
        ["g"] = { name = "+goto" },
        ["]"] = { name = "+next" },
        ["["] = { name = "+prev" },
        ["<leader>f"] = { name = "+file/find" },
        ["<leader>g"] = { name = "+git" },
        ["<leader>d"] = { name = "+debug" },
      },
    },
    config = function(_, opts)
      vim.o.timeout = true
      vim.o.timeoutlen = 300
      local wk = require("which-key")
      wk.setup(opts)
      wk.register(opts.defaults)
    end,
  },
  {
    "rest-nvim/rest.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = "http",
    opts = {
      result = {
        -- toggle showing URL, HTTP info, headers at top the of result window
        show_url = true,
        show_http_info = true,
        show_headers = true,
        -- executables or functions for formatting response body [optional]
        -- set them to false if you want to disable them
        formatters = {
          -- json = "jq",
          html = function(body)
            return vim.fn.system({ "tidy", "-i", "-q", "-" }, body)
          end,
        },
      },
    },
    config = function(_, opts)
      vim.keymap.set("n", "<leader>rr", "<Plug>RestNvim", { desc = "run the request under the cursor" })
      vim.keymap.set("n", "<leader>rp", "<Plug>RestNvimPreview", { desc = "preview the request cURL command" })
      vim.keymap.set("n", "<leader>rl", "<Plug>RestNvimLast", { desc = "re-run the last request" })
      require("rest-nvim").setup(opts)
    end,
  },
  {
    "vinnymeller/swagger-preview.nvim",
    build = "npm install -g swagger-ui-watcher",
    keys = {
      { "<leader>sp", ":SwaggerPreviewToggle<CR>", desc = "open swagger preview" },
    },
    opts = {
      -- The port to run the preview server on
      port = 8000,
      -- The host to run the preview server on
      host = "localhost",
    },
    config = function(_, opts)
      require("swagger-preview").setup(opts)
    end,
  },
  {
    "ekickx/clipboard-image.nvim",
    keys = {
      { "<leader>pi", ":PasteImg<CR>", desc = "paste image" },
    },
    opts = {
      default = {
        -- use the directory of your current file + img
        img_dir = { "%:p:h", "img" },
        img_name = function()
          vim.fn.inputsave()
          local name = vim.fn.input("Name: ")
          vim.fn.inputrestore()

          if name == nil or name == "" then
            return os.date("%y-%m-%d-%H-%M-%S")
          end
          return name
        end,
      },
    },
    config = function(_, opts)
      require("clipboard-image").setup(opts)
    end,
  },
  {
    "rmagatti/auto-session",
    config = function()
      require("auto-session").setup()
    end,
  },
  {
    "2nthony/sortjson.nvim",
    cmd = {
      "SortJSONByAlphaNum",
      "SortJSONByAlphaNumReverse",
      "SortJSONByKeyLength",
      "SortJSONByKeyLengthReverse",
    },
    config = true,
  },
  {
    "AckslD/nvim-neoclip.lua",
    dependencies = { "nvim-telescope/telescope.nvim" },
    -- load also with VeryLazy to not miss the first yanked/deleted text
    event = { "VeryLazy" },
    keys = {
      { "<leader>fy", ":Telescope neoclip<CR>", desc = "find yanked text over time" },
    },
    config = function()
      require("neoclip").setup()
      require("telescope").load_extension("neoclip")
    end,
  },
}
