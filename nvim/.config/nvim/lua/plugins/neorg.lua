return {
  "nvim-neorg/neorg",
  ft = "norg",
  dependencies = { "nvim-lua/plenary.nvim" },
  build = ":Neorg sync-parsers",
  -- temporal fix for https://github.com/nvim-neorg/neorg/issues/867
  tag = "v4.0.1",
  keys = {
    { "<leader>oo", ":Neorg index<CR>", desc = "open orgmode" },
    { "<leader>or", ":Neorg return<CR>", desc = "return from neorg" },
    { "<leader>ot", ":Neorg toggle-concealer<CR>", desc = "toggle concealer" },
  },
  opts = {
    load = {
      ["core.defaults"] = {}, -- Loads default behaviour
      ["core.concealer"] = {}, -- Adds pretty icons to your documents
      ["core.dirman"] = { -- Manages Neorg workspaces
        config = {
          workspaces = {
            work = "~/work/notes",
            personal = "~/personal/notes",
          },
          default_workspace = "work",
        },
      },
      ["core.completion"] = {
        config = { engine = "nvim-cmp" },
      },
    },
  },
}
