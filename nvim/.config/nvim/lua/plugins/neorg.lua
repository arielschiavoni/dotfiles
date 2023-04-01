return {
  "nvim-neorg/neorg",
  ft = "norg",
  dependencies = { "nvim-lua/plenary.nvim" },
  build = ":Neorg sync-parsers",
  keys = {
    { "<leader>on", ":Neorg index<CR>", { desc = "open neorg" } },
    { "<leader>or", ":Neorg return<CR>", { desc = "return from neorg" } },
    { "<leader>oc", ":Neorg toggle-concealer<CR>", { desc = "toggle concealer" } },
  },
  opts = {
    load = {
      ["core.defaults"] = {}, -- Loads default behaviour
      ["core.norg.concealer"] = {}, -- Adds pretty icons to your documents
      ["core.norg.dirman"] = { -- Manages Neorg workspaces
        config = {
          workspaces = {
            work = "~/work/notes",
            personal = "~/personal/notes",
          },
          default_workspace = "work",
        },
      },
      ["core.norg.completion"] = {
        config = { engine = "nvim-cmp" },
      },
    },
  },
}
