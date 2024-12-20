return {
  {
    "ellisonleao/gruvbox.nvim",
    lazy = true,
    config = function()
      require("gruvbox").setup({
        undercurl = true,
        underline = true,
        bold = true,
        italic = {
          strings = true,
          comments = true,
          operators = false,
          folds = true,
        },
        strikethrough = true,
        invert_selection = false,
        invert_signs = false,
        invert_tabline = false,
        invert_intend_guides = false,
        inverse = true, -- invert background for search, diffs, statuslines and errors
        contrast = "", -- can be "hard", "soft" or empty string
        palette_overrides = {},
        overrides = {},
        dim_inactive = false,
        transparent_mode = false,
      })
    end,
  },
  { "shaunsingh/oxocarbon.nvim", lazy = true },
  { "rose-pine/neovim", name = "rose-pine", lazy = true },
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        style = "moon",
        lualine_bold = true,
        on_highlights = function(hl, colors)
          hl.LineNr = {
            fg = "#636DA6",
          }
          hl.LineNrAbove = {
            fg = "#636DA6",
          }
          hl.LineNrBelow = {
            fg = "#636DA6",
          }
          hl.CursorLineNr = {
            fg = colors.orange,
          }
          hl.WinSeparator = {
            fg = colors.blue,
          }
        end,
      })
    end,
  },
}
