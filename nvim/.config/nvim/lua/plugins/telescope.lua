local function find_dotfiles()
  require("telescope.builtin").git_files({
    prompt_title = "< dotfiles >",
    cwd = vim.env.DOTFILES,
  })
end

-- find all files, including hidden and ignored by .gitignore
-- node_modules are globally ignored in ~/.config/fd/ignore
local function find_files()
  require("telescope.builtin").find_files({
    find_command = { "fd", "--type", "file", "--hidden", "--no-ignore-vcs", "--strip-cwd-prefix" },
  })
end

-- try to find files with git and if not found then fallback to find_files :-)
local function project_files()
  local ok = pcall(require("telescope.builtin").git_files, { show_untracked = true })
  if not ok then
    find_files()
  end
end

local function explore_files()
  require("telescope").extensions.file_browser.file_browser({ path = "%:p:h" })
end

local function git_worktrees()
  require("telescope").extensions.git_worktree.git_worktrees()
end

local function live_grep()
  require("telescope.builtin").live_grep({
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

return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-fzy-native.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
    "nvim-telescope/telescope-ui-select.nvim",
    {
      "ThePrimeagen/git-worktree.nvim",
      config = function()
        require("telescope").load_extension("git_worktree")
        local worktree = require("git-worktree")

        -- run external command when worktree changes
        worktree.on_tree_change(function(op, metadata)
          if op == worktree.Operations.Switch then
            print("Switched from " .. metadata.prev_path .. " to " .. metadata.path)
            local command = string.format(":silent !git-worktree-switcher %s", metadata.path)
            vim.cmd(command)
          end
        end)
      end,
    },
  },
  keys = {
    { "<leader>t", ":Telescope<CR>", { desc = "open telescope overwiew" } },
    { "<leader>p", project_files, { desc = "list git files respecting .gitignore" } },
    { "<leader>f", find_files, { desc = "list files in the current working directory" } },
    { "<leader>.", find_dotfiles, { desc = "list dotfiles" } },
    { "<leader>b", ":Telescope buffers<CR>", { desc = "list open buffers" } },
    { "<leader>e", explore_files, { desc = "explore files in the folder of the active buffer" } },
    { "<leader>s", live_grep, { desc = "search across current working directory" } },
    { "<leader>l", ":Telescope current_buffer_fuzzy_find<CR>", { desc = "search active buffer line" } },
    { "<leader>h", ":Telescope help_tags<CR>", { desc = "list help entries" } },
    { "<leader>k", ":Telescope keymaps<CR>", { desc = "list keymaps" } },
    { "<leader>gcc", ":Telescope git_commits<CR>", { desc = "list commits" } },
    { "<leader>gcb", ":Telescope git_bcommits<CR>", { desc = "list commits that changed the active buffer" } },
    { "<leader>gb", ":Telescope git_branches<CR>", { desc = "list branches" } },
    { "<leader>gw", git_worktrees, { desc = "list git worktrees" } },
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
    telescope.load_extension("ui-select")
  end,
}
