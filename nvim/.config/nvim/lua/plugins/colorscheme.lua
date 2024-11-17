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
        on_highlights = function(hl, colors)
          hl.LineNr = {
            fg = "#A1A8CA",
          }
          hl.LineNrAbove = {
            fg = "#A1A8CA",
          }
          hl.LineNrBelow = {
            fg = "#A1A8CA",
          }
          hl.CursorLineNr = {
            fg = colors.orange,
          }
        end,
      })
    end,
  },
}
