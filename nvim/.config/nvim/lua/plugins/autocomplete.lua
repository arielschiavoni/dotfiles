return {
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
      "rcarriga/cmp-dap",
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

      cmp.setup.filetype({ "dap-repl", "dapui_watches", "dapui_hover" }, {
        sources = {
          { name = "dap" },
        },
      })

      return {
        enabled = function()
          return vim.api.nvim_buf_get_option(0, "buftype") ~= "prompt" or require("cmp_dap").is_dap_buffer()
        end,
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
}
