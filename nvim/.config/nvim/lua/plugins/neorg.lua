return {
  "nvim-neorg/neorg",
  ft = "norg",
  dependencies = { "nvim-lua/plenary.nvim" },
  build = ":Neorg sync-parsers",
  keys = {
    { "<leader>ow", ":Neorg workspace work<CR>", desc = "open neorg work workspace" },
    { "<leader>op", ":Neorg workspace personal<CR>", desc = "open neorg personal workspace" },
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
