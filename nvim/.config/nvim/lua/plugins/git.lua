return {
  {
    "tpope/vim-fugitive",
    keys = {
      { "gs", ":G<CR>", desc = "git status" },
      { "gl", ":G log<CR>", desc = "git log" },
      { "<leader>gdh", ":diffget //2<CR>", desc = "use base diff buffer (//2 left" },
      { "<leader>gdl", ":diffget //3<CR>", desc = "use incoming diff buffer (//3 right)" },
    },
    config = function()
      vim.api.nvim_create_autocmd({ "FileType" }, {
        pattern = "fugitive",
        callback = function(args)
          local map = require("ariel.utils").create_buffer_keymaper(args.buf)
          map("n", "<leader>gp", ":G push --force-with-lease<CR>", { desc = "Push force with lease" })
          map("n", "<leader>gu", ":G push -u origin HEAD<CR>", { desc = "Push and set origin upstream" })
          map("n", "<leader>gP", ":G pull<CR>", { desc = "Pull" })
          map("n", "<leader>gri", function()
            local last_n_commits = vim.fn.input("Rebase the last N commits > ")
            vim.cmd(string.format("G rebase -i HEAD~%s", last_n_commits))
          end, { desc = "Rebase interactive for the last N commits" })
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
          local map = require("ariel.utils").create_buffer_keymaper(bufnr)
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
          map({ "n", "v" }, "<leader>hs", ":Gitsigns stage_hunk<CR>", { desc = "git stage hunk" })
          map({ "n", "v" }, "<leader>hr", ":Gitsigns reset_hunk<CR>", { desc = "git reset hunk" })
          map("n", "<leader>hS", gs.stage_buffer, { desc = "git stage buffer" })
          map("n", "<leader>hu", gs.undo_stage_hunk, { desc = "git undo stage hunk" })
          map("n", "<leader>hR", gs.reset_buffer, { desc = "git reset buffer" })
          map("n", "<leader>hp", gs.preview_hunk, { desc = "git preview hunk" })
          map("n", "<leader>hb", function()
            gs.blame_line({ full = true })
          end, { desc = "git blame line" })
          map("n", "<leader>tb", gs.toggle_current_line_blame, { desc = "git toggle current line blame" })
          map("n", "<leader>hd", gs.diffthis, { desc = "git diff this" })
          map("n", "<leader>hD", function()
            gs.diffthis("~")
          end, { desc = "git diff this against ~" })
          map("n", "<leader>td", gs.toggle_deleted, { desc = "git toggle deleted" })

          -- Text object (in visual mode (x) you can can select the hunk. vih -> select inside hunk, similar to selecting a word or paragraph
          map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "git select hunk" })
        end,
      })
    end,
  },
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>gdo", ":DiffviewOpen<CR>", desc = "open diff view" },
      { "<leader>gdf", ":DiffviewFileHistory<CR>", desc = "open diff view git history" },
      { "<leader>gdm", ":DiffviewOpen main<CR>", desc = "open diff view agains main branch" },
      { "<leader>gdb", ":DiffviewFileHistory %<CR>", desc = "open file history diff" },
      { "<leader>gdc", ":DiffviewClose<CR>", desc = "close diff view" },
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
  {
    "aaronhallaert/advanced-git-search.nvim",
    dependencies = {
      "tpope/vim-fugitive",
      "tpope/vim-rhubarb",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    keys = {
      {
        "gS",
        ":AdvancedGitSearch<CR>",
        desc = "advanced git search",
      },
      {
        "fc%",
        function()
          require("telescope").extensions.advanced_git_search.diff_commit_file()
        end,
        desc = "find commits that affected current buffer",
      },
      {
        "fcs",
        function()
          require("telescope").extensions.advanced_git_search.diff_commit_line()
        end,
        desc = "find commits that affected the selected lines",
        mode = "v",
      },
    },
    config = function()
      -- optional: setup telescope before loading the extension
      require("telescope").setup({
        -- move this to the place where you call the telescope setup function
        extensions = {
          advanced_git_search = {
            diff_plugin = "diffview",
            entry_default_author_or_date = "author", -- one of "author" or "date"
            git_flags = { "-c", "delta.side-by-side=false" },
            -- git_flags = { "--no-pager" },
            git_diff_flags = {},
            show_builtin_git_pickers = true,
          },
        },
      })

      require("telescope").load_extension("advanced_git_search")
    end,
  },
  {
    "ThePrimeagen/git-worktree.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    keys = {
      {
        "<leader>gw",
        function()
          require("telescope").extensions.git_worktree.git_worktrees()
        end,
        desc = "find git worktrees",
      },
    },
    config = function()
      require("telescope").load_extension("git_worktree")
    end,
  },
  {
    "ruifm/gitlinker.nvim",
    keys = {
      {
        "<leader>gly",
        function()
          require("gitlinker").get_buf_range_url("n")
        end,
        mode = "n",
        desc = "copy current line git permalink to clipboard",
      },
      {
        "<leader>gly",
        function()
          require("gitlinker").get_buf_range_url("v")
        end,
        mode = "v",
        desc = "copy line range git permalink to clipboard",
      },
      {
        "<leader>glb",
        function()
          require("gitlinker").get_buf_range_url(
            "n",
            { action_callback = require("gitlinker.actions").open_in_browser }
          )
        end,
        mode = "n",
        desc = "open current line git permalink in browser",
      },
      {
        "<leader>glb",
        function()
          require("gitlinker").get_buf_range_url(
            "v",
            { action_callback = require("gitlinker.actions").open_in_browser }
          )
        end,
        mode = "v",
        desc = "open line range git permalink in browser",
      },
      {
        "<leader>glY",
        function()
          require("gitlinker").get_repo_url()
        end,
        desc = "copy git repo url to clipboard",
      },
      {
        "<leader>glB",
        function()
          require("gitlinker").get_repo_url({ action_callback = require("gitlinker.actions").open_in_browser })
        end,
        desc = "open git repo url in browser",
      },
    },
  },
}
