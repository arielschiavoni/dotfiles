return {
  "saghen/blink.cmp",

  event = { "InsertEnter" },

  dependencies = {
    "moyiz/blink-emoji.nvim",
    "L3MON4D3/LuaSnip",
  },

  -- use a release tag to download pre-built binaries
  version = "*",

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    -- 'default' for mappings similar to built-in completion
    -- 'super-tab' for mappings similar to vscode (tab to accept, arrow keys to navigate)
    -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
    -- See the full "keymap" documentation for information on defining your own keymap.
    keymap = {
      preset = "enter",
      ["<C-y>"] = { "select_and_accept" },
    },

    completion = {
      menu = {
        border = "single",
      },
      documentation = {
        auto_show = true,
        window = {
          border = "single",
        },
      },
      -- Displays a preview of the selected item on the current line
      ghost_text = {
        enabled = true,
      },
    },

    appearance = {
      -- Sets the fallback highlight groups to nvim-cmp's highlight groups
      -- Useful for when your theme doesn't support blink.cmp
      -- Will be removed in a future release
      use_nvim_cmp_as_default = true,
      -- Set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      -- Adjusts spacing to ensure icons are aligned
      nerd_font_variant = "mono",
    },

    signature = {
      enabled = true,
      window = { border = "single" },
    },

    snippets = { preset = "luasnip" },

    sources = {
      per_filetype = {
        codecompanion = { "codecompanion" },
      },
      default = {
        -- built-in providers
        "lsp",
        "path",
        "snippets",
        "buffer",
        -- plugins
        "emoji",
      },
      providers = {
        emoji = {
          module = "blink-emoji",
          name = "Emoji",
          score_offset = 15, -- Tune by preference
          opts = { insert = true }, -- Insert emoji (default) or complete its name
        },
      },
    },
  },
}
