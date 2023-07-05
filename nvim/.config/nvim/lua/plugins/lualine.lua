-- +-------------------------------------------------+
-- | A | B | C                             X | Y | Z |
-- +-------------------------------------------------+
return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  config = function()
    require("lualine").setup({
      options = {
        theme = "tokyonight",
      },
      sections = {
        -- https://github.com/nvim-lualine/lualine.nvim#filename-component-options
        -- disable filename, it is shown top right in the winbar
        lualine_c = {},
        lualine_y = { "filetype", "filesize" },
      },
    })
  end,
}
