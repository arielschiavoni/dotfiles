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
    "mhartington/formatter.nvim",
    event = "VeryLazy",
    config = function()
      local util = require("formatter.util")
      local filetypes = {
        -- Formatter configurations for filetype "lua" go here
        -- and will be executed in order
        lua = {
          -- "formatter.filetypes.lua" defines default configurations for the
          -- "lua" filetype
          require("formatter.filetypes.lua").stylua,

          -- You can also define your own configuration
          function()
            -- Full specification of configurations is down below and in Vim help
            -- files
            return {
              exe = "stylua",
              args = {
                "--indent-width",
                "2",
                "--indent-type",
                "Spaces",
                "--search-parent-directories",
                "--stdin-filepath",
                util.escape_path(util.get_current_buffer_file_path()),
                "--",
                "-",
              },
              stdin = true,
            }
          end,
        },
        -- Use the special "*" filetype for defining formatter configurations on
        -- any filetype
        ["*"] = {
          -- "formatter.filetypes.any" defines default configurations for any
          -- filetype
          require("formatter.filetypes.any").remove_trailing_whitespace,
        },
      }

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

      local prettierd = require("formatter.defaults.prettierd")

      for _, prettier_filetype in ipairs(prettier_filetypes) do
        filetypes[prettier_filetype] = { prettierd }
      end

      require("formatter").setup({
        logging = false,
        log_level = vim.log.levels.INFO,
        filetype = filetypes,
      })

      vim.api.nvim_create_autocmd("BufWritePost", {
        command = "FormatWrite",
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
    -- todo compare to debugloop/telescope-undo.nvim
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
      -- https://github.com/stevearc/oil.nvim#options
      view_options = {
        -- Show files and directories that start with "."
        show_hidden = true,
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
    "ruifm/gitlinker.nvim",
    keys = {
      {
        "<leader>gly",
        function()
          require("gitlinker").get_buf_range_url("n")
        end,
        mode = "n",
        desc = "copy current line git permalink to clipboard",
      },
      {
        "<leader>gly",
        function()
          require("gitlinker").get_buf_range_url("v")
        end,
        mode = "v",
        desc = "copy line range git permalink to clipboard",
      },
      {
        "<leader>glb",
        function()
          require("gitlinker").get_buf_range_url(
            "n",
            { action_callback = require("gitlinker.actions").open_in_browser }
          )
        end,
        mode = "n",
        desc = "open current line git permalink in browser",
      },
      {
        "<leader>glb",
        function()
          require("gitlinker").get_buf_range_url(
            "v",
            { action_callback = require("gitlinker.actions").open_in_browser }
          )
        end,
        mode = "v",
        desc = "open line range git permalink in browser",
      },
      {
        "<leader>glY",
        function()
          require("gitlinker").get_repo_url()
        end,
        desc = "copy git repo url to clipboard",
      },
      {
        "<leader>glB",
        function()
          require("gitlinker").get_repo_url({ action_callback = require("gitlinker.actions").open_in_browser })
        end,
        desc = "open git repo url in browser",
      },
    },
  },
  {
    "folke/persistence.nvim",
    keys = {
      {
        "<leader>qs",
        function()
          require("persistence").load()
        end,
        desc = "restore session for current directory",
      },
      {
        "<leader>ql",
        function()
          require("persistence").load({ last = true })
        end,
        desc = "restore last session",
      },
      {
        "<leader>qd",
        function()
          require("persistence").stop()
        end,
        desc = "stop Persistence => session won't be saved on exit",
      },
    },
    opts = {
      dir = vim.fn.expand(vim.fn.stdpath("state") .. "/sessions/"), -- directory where session files are saved
      options = { "buffers", "curdir", "tabpages", "winsize" }, -- vim.o.sessionoptions used for saving
      pre_save = nil, -- a function to call before saving the session
    },
    config = function(_, opts)
      require("persistence").setup(opts)
    end,
  },
}
