return {
  "NeogitOrg/neogit",
  keys = {
    { "gs", ":Neogit kind=split<CR>", desc = "Neogit Status" },
    { "<leader>gf", ":Neogit fetch kind=split<CR>", desc = "Neogit Fetch" },
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
  },
  config = function()
    local neogit = require("neogit")
    -- https://github.com/NeogitOrg/neogit?tab=readme-ov-file#configuration
    neogit.setup({
      use_per_project_settings = false,
      commit_editor = {
        kind = "split",
        show_staged_diff = false,
        spell_check = true,
      },
      mappings = {
        status = {
          ["a"] = "Stage",
          -- disable "s" (default for stage) to enable jumping with flash.nvim default keymap
          ["s"] = false,
        },
      },
    })
  end,
}
