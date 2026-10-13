return {
  "georgeguimaraes/review.nvim",
  version = "*",
  dependencies = {
    {
      "esmuellert/codediff.nvim",
      opts = {
        explorer = {
          view_mode = "tree",
        },
        keymaps = {
          view = {
            stage_hunk = "a",
            unstage_hunk = "r",
          },
        },
      },
    },
    "MunifTanjim/nui.nvim",
  },
  event = "VeryLazy",
  keys = {
    { "<leader>rr", "<cmd>Review<cr>", desc = "Review working tree" },
    { "<leader>rc", "<cmd>Review commits<cr>", desc = "Review commits" },
    { "<leader>rb", "<cmd>Review branch<cr>", desc = "Review branch" },
    { "<leader>ra", ":Review note<cr>", mode = { "n", "v" }, desc = "Review: add note here" },
    { "<leader>re", "<cmd>Review edit<cr>", desc = "Review: edit comment" },
    { "<leader>rd", "<cmd>Review delete<cr>", desc = "Review: delete comment" },
    { "<leader>rx", "<cmd>Review export<cr>", desc = "Review: export" },
  },
  opts = {},
}
