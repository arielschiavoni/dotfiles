local function create_buffer_keymaper(buffer)
  return function(mode, l, r, opts)
    opts = opts or {}
    opts.buffer = buffer
    opts.remap = false
    vim.keymap.set(mode, l, r, opts)
  end
end

return {
  {
    "tpope/vim-fugitive",
    keys = {
      { "gs", ":G<CR>", { desc = "git status" } },
      { "gl", ":G log<CR>", { desc = "git log" } },
      { "gdh", ":diffget //2<CR>", { desc = "use base diff buffer (//2 left" } },
      { "gdl", ":diffget //3<CR>", { desc = "use incoming diff buffer (//3 right)" } },
    },
    config = function()
      vim.api.nvim_create_autocmd({ "FileType" }, {
        pattern = "fugitive",
        callback = function(args)
          local map = create_buffer_keymaper(args.buf)
          map("n", "<leader>p", ":G push --force-with-lease<CR>", { desc = "git push force with lease" })
          map("n", "<leader>pu", ":G push -u origin HEAD<CR>", { desc = "git push and set upstream branch" })
          map("n", "<leader>P", ":G pull<CR>", { desc = "git pull" })
          map("n", "<leader>ri", function()
            local last_n_commits = vim.fn.input("Rebase the last N commits > ")
            vim.cmd(string.format("G rebase -i HEAD~%s", last_n_commits))
          end, { desc = "git rebase interactive for the last N commits" })
        end,
      })
    end,
  },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns
          local map = create_buffer_keymaper(bufnr)
          -- Navigation
          map("n", "]c", function()
            if vim.wo.diff then
              return "]c"
            end
            vim.schedule(function()
              gs.next_hunk()
            end)
            return "<Ignore>"
          end, { expr = true })

          map("n", "[c", function()
            if vim.wo.diff then
              return "[c"
            end
            vim.schedule(function()
              gs.prev_hunk()
            end)
            return "<Ignore>"
          end, { expr = true })

          -- Actions
          map({ "n", "v" }, "<leader>hs", ":Gitsigns stage_hunk<CR>")
          map({ "n", "v" }, "<leader>hr", ":Gitsigns reset_hunk<CR>")
          map("n", "<leader>hS", gs.stage_buffer)
          map("n", "<leader>hu", gs.undo_stage_hunk)
          map("n", "<leader>hR", gs.reset_buffer)
          map("n", "<leader>hp", gs.preview_hunk)
          map("n", "<leader>hb", function()
            gs.blame_line({ full = true })
          end)
          map("n", "<leader>tb", gs.toggle_current_line_blame)
          map("n", "<leader>hd", gs.diffthis)
          map("n", "<leader>hD", function()
            gs.diffthis("~")
          end)
          map("n", "<leader>td", gs.toggle_deleted)

          -- Text object
          map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>")
        end,
      })
    end,
  },
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>do", ":DiffviewOpen<CR>", { desc = "open diff view" } },
      { "<leader>df", ":DiffviewFileHistory<CR>", { desc = "open diff view git history" } },
      { "<leader>dm", ":DiffviewOpen main<CR>", { desc = "open diff view agains main branch" } },
      { "<leader>db", ":DiffviewFileHistory %<CR>", { desc = "open file history diff" } },
      { "<leader>dc", ":DiffviewClose<CR>", { desc = "close diff view" } },
    },
    config = function()
      require("diffview").setup({
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
      })
    end,
  },
}
