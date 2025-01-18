return {
  {
    "NeogitOrg/neogit",
    keys = {
      { "gs", ":Neogit kind=split<CR>", desc = "Neogit Status" },
      { "<leader>gf", ":Neogit fetch kind=split<CR>", desc = "Neogit Fetch" },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
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
  },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        on_attach = function(bufnr)
          local gs = require("gitsigns")

          local map = require("ariel.utils").create_buffer_keymaper(bufnr)
          -- Navigation
          map("n", "]c", function()
            if vim.wo.diff then
              vim.cmd.normal({ "]c", bang = true })
            else
              gs.nav_hunk("next")
            end
          end)

          map("n", "[c", function()
            if vim.wo.diff then
              vim.cmd.normal({ "[c", bang = true })
            else
              gs.nav_hunk("prev")
            end
          end)

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
  },
  {
    "polarmutex/git-worktree.nvim",
    version = "^2",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
    keys = {
      {
        "<leader>gw",
        function()
          require("telescope").extensions.git_worktree.git_worktree()
        end,
        desc = "find git worktrees",
      },
    },
    config = function()
      require("telescope").load_extension("git_worktree")
      local Hooks = require("git-worktree.hooks")

      Hooks.register(Hooks.type.SWITCH, function(path, prev_path)
        local relativePath = path:gsub("^" .. os.getenv("HOME"), "")
        vim.notify("Switched to ~" .. relativePath)

        local bufnr = vim.api.nvim_get_current_buf()
        local filetype = vim.api.nvim_buf_get_option(bufnr, "ft")
        if filetype == "oil" then
          local ok, oil = pcall(require, "oil")
          if ok then
            oil.open(path)
          else
            vim.notify("Oil is not ready to be used by git_worktree", vim.log.levels.ERROR)
          end
        else
          Hooks.builtins.update_current_buffer_on_switch(path, prev_path)
        end
      end)
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
  {

    "pwntester/octo.nvim",
    event = { "VeryLazy" },
    requires = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      -- https://github.com/pwntester/octo.nvim?tab=readme-ov-file#-configuration
      require("octo").setup({
        -- default_to_projects_v2 = true,
        suppress_missing_scope = {
          projects_v2 = true,
        },
      })
    end,
  },
}
