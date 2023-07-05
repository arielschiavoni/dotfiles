-- +-------------------------------------------------+
-- | A | B | C                             X | Y | Z |
-- +-------------------------------------------------+
return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  config = function()
    local noice = require("noice")

    require("lualine").setup({
      options = {
        theme = "tokyonight",
      },
      sections = {
        -- https://github.com/nvim-lualine/lualine.nvim#filename-component-options
        -- disable filename, it is shown top right in the winbar
        lualine_c = {},
        lualine_x = {
          {
            function()
              local msg = noice.api.statusline.mode.get()
              local result, numReplacements = string.gsub(msg, ".*(%brecording.*)", "%1")
              if numReplacements == 0 then
                -- Set result to an empty string if "recording" is not found
                return ""
              end

              return " " .. result
            end,
            cond = noice.api.statusline.mode.has,
            color = { fg = "#ff9e64" },
          },
        },
        lualine_y = { "filetype", "filesize" },
      },
    })
  end,
}
