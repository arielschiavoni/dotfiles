return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-fzy-native.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
    "nvim-telescope/telescope-ui-select.nvim",
    "ThePrimeagen/git-worktree.nvim", -- defined git_worktree extension
  },
  config = function()
    local telescope = require("telescope")
    local sorters = require("telescope.sorters")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local actions_layout = require("telescope.actions.layout")
    local themes = require("telescope.themes")

    telescope.setup({
      defaults = {
        file_sorter = sorters.get_fzy_sorter,
        prompt_prefix = "> ",
        color_devicons = true,

        file_previewer = previewers.vim_buffer_cat.new,
        grep_previewer = previewers.vim_buffer_vimgrep.new,
        qflist_previewer = previewers.vim_buffer_qflist.new,

        mappings = {
          i = {
            ["<esc>"] = actions.close,
            ["<C-q>"] = actions.send_to_qflist,
            ["<C-j>"] = actions.cycle_previewers_next,
            ["<C-k>"] = actions.cycle_previewers_prev,
            ["<M-p>"] = actions_layout.toggle_preview,
          },
          n = {
            ["<M-p>"] = actions_layout.toggle_preview,
          },
        },
      },
      extensions = {
        fzy_native = {
          override_generic_sorter = false,
          override_file_sorter = true,
        },
        ["ui-select"] = {
          themes.get_dropdown(),
        },
      },
    })

    -- extensions
    telescope.load_extension("fzy_native")
    telescope.load_extension("file_browser")
    telescope.load_extension("git_worktree")
    telescope.load_extension("ui-select")

    -- keymaps
    local extensions = require("telescope").extensions
    local builtin = require("telescope.builtin")
    local file_browser = telescope.extensions.file_browser

    local find_dotfiles = function()
      builtin.git_files({
        prompt_title = "< dotfiles >",
        cwd = vim.env.DOTFILES,
      })
    end

    -- find all files, including hidden and ignored by .gitignore
    -- node_modules are globally ignored in ~/.config/fd/ignore
    local find_files = function()
      builtin.find_files({
        find_command = { "fd", "--type", "file", "--hidden", "--no-ignore-vcs", "--strip-cwd-prefix" },
      })
    end

    -- try to find files with git and if not found then fallback to find_files :-)
    local project_files = function()
      local ok = pcall(builtin.git_files, { show_untracked = true })
      if not ok then
        find_files()
      end
    end

    local explore_files = function()
      file_browser.file_browser({ path = "%:p:h" })
    end

    local live_grep = function()
      builtin.live_grep({
        vimgrep_arguments = {
          "rg",
          "--color=never",
          "--no-heading",
          "--with-filename",
          "--line-number",
          "--column",
          "--smart-case",
          "--trim",
          "--hidden",
          "-g",
          "!node_modules/**",
          "-g",
          "!.git/**",
        },
      })
    end

    vim.keymap.set("n", "<leader>t", ":Telescope<CR>", { desc = "open telescope overwiew" })
    vim.keymap.set("n", "<leader>p", project_files, { desc = "list git files respecting .gitignore" })
    vim.keymap.set("n", "<leader>f", find_files, { desc = "list files in the current working directory" })
    vim.keymap.set("n", "<leader>.", find_dotfiles, { desc = "list dotfiles" })
    vim.keymap.set("n", "<leader>b", builtin.buffers, { desc = "list open buffers" })
    vim.keymap.set("n", "<leader>e", explore_files, { desc = "explore files in the folder of the active buffer" })
    vim.keymap.set("n", "<leader>s", live_grep, { desc = "search across current working directory" })
    vim.keymap.set("n", "<leader>l", builtin.current_buffer_fuzzy_find, { desc = "search active buffer line" })
    vim.keymap.set("n", "<leader>h", builtin.help_tags, { desc = "list help entries" })
    vim.keymap.set("n", "<leader>k", builtin.keymaps, { desc = "list keymaps" })
    vim.keymap.set("n", "<leader>gc", builtin.git_commits, { desc = "list commits" })
    vim.keymap.set("n", "<leader>gb", builtin.git_bcommits, { desc = "list commits that changed the active buffer" })
    vim.keymap.set("n", "<leader>gw", extensions.git_worktree.git_worktrees, { desc = "list git worktrees" })
  end,
}
