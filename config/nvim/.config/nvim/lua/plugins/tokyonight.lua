return {
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
}
