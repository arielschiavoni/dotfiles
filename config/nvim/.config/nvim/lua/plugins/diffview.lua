return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gdo", ":DiffviewOpen<CR>", desc = "open diff view" },
    { "<leader>gdf", ":DiffviewFileHistory<CR>", desc = "open diff view git history" },
    { "<leader>gdm", ":DiffviewOpen main<CR>", desc = "open diff view agains main branch" },
    { "<leader>gdc", ":DiffviewClose<CR>", desc = "close diff view" },
    { "<leader>gdb", ":DiffviewFileHistory % --follow<CR>", desc = "open current file history" },
    {
      "<leader>gds",
      ":'<,'>DiffviewFileHistory--follow<CR>",
      desc = "open visual selection history",
      mode = { "v" },
    },
  },
  config = function()
    require("diffview").setup({
      default_args = {
        -- useful to review PR and have LSP support
        -- https://github.com/sindrets/diffview.nvim/blob/main/USAGE.md#review-a-pr
        DiffviewOpen = { "--imply-local" },
      },
      enhanced_diff_hl = true,
      file_panel = {
        listing_style = "tree",
        tree_options = {
          flatten_dirs = true,
          folder_statuses = "only_folded",
        },
        win_config = {
          position = "bottom",
          height = 20,
        },
      },
      file_history_panel = {
        log_options = {
          git = {
            -- See |diffview-config-log_options|
            single_file = {
              max_count = 1000,
            },
            multi_file = {
              max_count = 1000,
            },
          },
        },
      },
    })
  end,
}
