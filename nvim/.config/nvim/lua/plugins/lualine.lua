-- +-------------------------------------------------+
-- | A | B | C                             X | Y | Z |
-- +-------------------------------------------------+
return {
  "nvim-lualine/lualine.nvim",
  config = {
    options = {
      -- https://github.com/nvim-lualine/lualine.nvim#global-options
      -- one single status line for multiple windows
      globalstatus = true,
    },
    sections = {
      -- https://github.com/nvim-lualine/lualine.nvim#filename-component-options
      -- configure filename to show relative path
      lualine_c = { { "filename", path = 1 } },
      lualine_x = { "filetype", "filesize" },
    },
  },
}
