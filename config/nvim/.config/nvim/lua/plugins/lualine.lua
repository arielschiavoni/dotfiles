return {
  -- +-------------------------------------------------+
  -- | A | B | C                             X | Y | Z |
  -- +-------------------------------------------------+
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  config = function()
    require("lualine").setup({
      sections = {
        -- https://github.com/nvim-lualine/lualine.nvim#filename-component-options
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 3 } },
        lualine_x = { "encoding", "fileformat", "filetype", "filesize" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
      extensions = { "quickfix", "man", "fugitive", "oil", "nvim-dap-ui" },
    })
  end,
}
