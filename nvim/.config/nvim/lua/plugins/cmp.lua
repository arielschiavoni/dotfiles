return {
  "hrsh7th/nvim-cmp",
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
    "onsails/lspkind.nvim",
    "L3MON4D3/LuaSnip",
    "rafamadriz/friendly-snippets",
  },
  config = function()
    local luasnip = require("luasnip")
    local types = require("luasnip.util.types")

    luasnip.config.set_config({
      -- This tells LuaSnip to remember to keep around the last snippet.
      -- You can jump back into it even if you move outside of the selection
      history = true,

      -- This one is cool cause if you have dynamic snippets, it updates as you type!
      updateevents = "TextChanged,TextChangedI",

      -- Autosnippets:
      enable_autosnippets = true,

      -- Crazy highlights!!
      -- #vid3
      -- ext_opts = nil,
      ext_opts = {
        [types.choiceNode] = {
          active = {
            virt_text = { { "<-", "Error" } },
          },
        },
      },
    })

    -- Load snippets from JSON files (VSCode syntax)
    -- https://github.com/L3MON4D3/LuaSnip#add-snippets
    require("luasnip.loaders.from_vscode").lazy_load()

    local has_words_before = function()
      local line, col = unpack(vim.api.nvim_win_get_cursor(0))
      return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
    end

    local cmp = require("cmp")
    local lspkind = require("lspkind")

    local function tab(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      elseif has_words_before() then
        cmp.complete()
      else
        -- F("<Tab>")
        fallback()
      end
    end

    local function shtab(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      elseif luasnip.jumpable(-1) then
        luasnip.jump(-1)
      else
        -- F('<S-Tab>')
        fallback()
      end
    end

    local function enterit(fallback)
      if cmp.visible() and cmp.get_selected_entry() then
        cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = false })
      else
        -- F("<CR>")
        fallback()
      end
    end

    -- creates source configuration with 10 max items by default
    local function create_source_configs(max_item_count)
      max_item_count = max_item_count or 10
      local sources = { "nvim_lsp", "luasnip", "nvim_lua", "path", "emoji", "buffer", "cmdline", "cmdline_history" }
      local source_configs = {}

      for _, source in ipairs(sources) do
        source_configs[source] = { name = source, max_item_count = max_item_count }
      end

      return source_configs
    end

    local source_configs = create_source_configs()

    cmp.setup({
      -- https://github.com/hrsh7th/nvim-cmp/wiki/Menu-Appearance
      view = {
        entries = { name = "custom" },
      },
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = {
        ["<C-d>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<Tab>"] = cmp.mapping(tab, { "i", "s", "c" }),
        ["<S-Tab>"] = cmp.mapping(shtab, { "i", "s", "c" }),
        ["<CR>"] = cmp.mapping(enterit, { "i", "s" }),
      },
      sources = cmp.config.sources({
        source_configs["nvim_lsp"],
        source_configs["luasnip"],
        source_configs["nvim_lua"],
        source_configs["path"],
      }, {
        source_configs["emoji"],
        source_configs["buffer"],
      }),
      window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
      },
      formatting = {
        format = lspkind.cmp_format({
          mode = "symbol", -- show only symbol
          maxwidth = 50, -- prevent the popup from showing more than provided characters (e.g 50 will not show more than 50 characters)
          menu = {
            nvim_lsp = "[LSP]",
            luasnip = "[LuaSnip]",
            buffer = "[Buffer]",
            nvim_lua = "[Lua]",
            cmdline = "[Cmd]",
            cmdline_history = "[CmdHistory]",
            path = "[Path]",
            emoji = "[Emoji]",
          },
        }),
      },
    })

    -- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
    cmp.setup.cmdline("/", {
      mapping = cmp.mapping.preset.cmdline(),
      sources = {
        source_configs["buffer"],
      },
    })

    -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
    cmp.setup.cmdline(":", {
      mapping = cmp.mapping.preset.cmdline(),
      sources = cmp.config.sources({
        source_configs["path"],
      }, {
        source_configs["cmdline"],
        source_configs["cmdline_history"],
      }),
    })
  end,
}
