return {
  {
    "echasnovski/mini.surround",
    version = false,
    event = "VeryLazy",
    config = function()
      require("mini.surround").setup( -- No need to copy this inside `setup()`. Will be used automatically.
        {
          -- Add custom surroundings to be used on top of builtin ones. For more
          -- information with examples, see `:h MiniSurround.config`.
          custom_surroundings = nil,

          -- Duration (in ms) of highlight when calling `MiniSurround.highlight()`
          highlight_duration = 500,

          -- Module mappings. Use `''` (empty string) to disable one.
          mappings = {
            add = "<leader>sa", -- Add surrounding in Normal and Visual modes
            delete = "<leader>sd", -- Delete surrounding
            find = "<leader>sf", -- Find surrounding (to the right)
            find_left = "<leader>sF", -- Find surrounding (to the left)
            highlight = "<leader>sh", -- Highlight surrounding
            replace = "<leader>sr", -- Replace surrounding
            update_n_lines = "<leader>sn", -- Update `n_lines`

            suffix_last = "l", -- Suffix to search with "prev" method
            suffix_next = "n", -- Suffix to search with "next" method
          },

          -- Number of lines within which surrounding is searched
          n_lines = 20,

          -- Whether to respect selection type:
          -- - Place surroundings on separate lines in linewise mode.
          -- - Place surroundings on each line in blockwise mode.
          respect_selection_type = false,

          -- How to search for surrounding (first inside current line, then inside
          -- neighborhood). One of 'cover', 'cover_or_next', 'cover_or_prev',
          -- 'cover_or_nearest', 'next', 'prev', 'nearest'. For more details,
          -- see `:h MiniSurround.config`.
          search_method = "cover",

          -- Whether to disable showing non-error feedback
          silent = false,
        }
      )
    end,
  },
  {
    "echasnovski/mini.indentscope",
    version = false,
    event = "VeryLazy",
    config = function()
      local indentscope = require("mini.indentscope")

      indentscope.setup({
        -- Draw options
        draw = {
          -- Delay (in ms) between event and start of drawing scope indicator
          delay = 100,
          animation = indentscope.gen_animation.none(),
        },

        -- Module mappings. Use `''` (empty string) to disable one.
        mappings = {
          -- Textobjects
          object_scope = "ii",
          object_scope_with_border = "ai",

          -- Motions (jump to respective border line; if not present - body line)
          goto_top = "[i",
          goto_bottom = "]i",
        },

        -- Options which control scope computation
        options = {
          -- Type of scope's border: which line(s) with smaller indent to
          -- categorize as border. Can be one of: 'both', 'top', 'bottom', 'none'.
          border = "both",

          -- Whether to use cursor column when computing reference indent.
          -- Useful to see incremental scopes with horizontal cursor movements.
          indent_at_cursor = true,

          -- Whether to first check input line to be a border of adjacent scope.
          -- Use it if you want to place cursor on function header to get scope of
          -- its body.
          try_as_border = false,
        },

        -- Which character to use for drawing scope indicator
        symbol = "╎",
      })
    end,
  },
  {
    -- complementary pairs of mappings (for quickfixlist [q, ]q, add spaces before or after line [<Space>)
    "tpope/vim-unimpaired",
    event = "VeryLazy",
  },
  {
    "norcalli/nvim-colorizer.lua",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("colorizer").setup()
    end,
  },
  {
    "rcarriga/nvim-notify",
    dependencies = { "nvim-telescope/telescope.nvim" },
    event = "VeryLazy",
    keys = {
      { "<leader>fn", ":Telescope notify<CR>", desc = "find notifications" },
    },
    config = function()
      vim.notify = require("notify")
      require("telescope").load_extension("notify")
    end,
  },
  {
    "folke/ts-comments.nvim",
    opts = {},
    event = "VeryLazy",
  },
  {
    -- allows to keep registers (yanked, deleted text) in a history searcheable by telescope
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
