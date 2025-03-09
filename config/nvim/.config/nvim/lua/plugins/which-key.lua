return {
  -- show keymaps on the go
  "folke/which-key.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>?",
      function()
        require("which-key").show({ global = false })
      end,
      desc = "Buffer Local Keymaps (which-key)",
    },
    {
      "<leader>!",
      function()
        require("which-key").show({ global = true })
      end,
      desc = "Global Keymaps (which-key)",
    },
  },
  opts = {
    -- show a warning when issues were detected with your mappings
    notify = true,
    --- You can add any mappings here, or use `require('which-key').add()` later
    ---@type wk.Spec
    spec = {
      {
        mode = { "n", "v" },
        { "<leader>d", group = "debug" },
        { "<leader>f", group = "file/find" },
        { "[", group = "prev" },
        { "]", group = "next" },
        { "g", group = "goto" },
      },
    },
  },
}
