return {
  "nvim-neorg/neorg",
  ft = "norg",
  dependencies = { "nvim-lua/plenary.nvim" },
  build = ":Neorg sync-parsers",
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
