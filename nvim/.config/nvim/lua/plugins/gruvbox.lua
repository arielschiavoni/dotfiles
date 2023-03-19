return {
  "ellisonleao/gruvbox.nvim",
  config = function()
    require("gruvbox").setup({
      undercurl = true,
      underline = true,
      bold = true,
      italic = true,
      strikethrough = true,
      invert_selection = false,
      invert_signs = false,
      invert_tabline = false,
      invert_intend_guides = false,
      inverse = true, -- invert background for search, diffs, statuslines and errors
      contrast = "", -- can be "hard", "soft" or empty string
      palette_overrides = {},
      overrides = {
        -- DiffText = { bg = "#b8bb26" },
        -- DiffAdd = { bg = "#83a598" },
      },
      dim_inactive = false,
      transparent_mode = false,
    })
  end,
}
