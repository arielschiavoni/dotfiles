-- +-------------------------------------------------+
-- | A | B | C                             X | Y | Z |
-- +-------------------------------------------------+
return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "kyazdani42/nvim-web-devicons" },
  event = "VeryLazy",
  config = {
    options = {
      theme = "tokyonight",
    },
    sections = {
      -- https://github.com/nvim-lualine/lualine.nvim#filename-component-options
      -- configure filename to show relative path
      lualine_c = { { "filename", path = 1 } },
      lualine_x = { "filetype", "filesize" },
    },
  },
}
