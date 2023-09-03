local function find_dotfiles()
  require("telescope.builtin").git_files({
    prompt_title = "< dotfiles >",
    cwd = vim.env.DOTFILES,
  })
end

-- find all files, including hidden and ignored by .gitignore or ~/.config/fd/ignore
local function find_all_files()
  require("telescope.builtin").find_files({
    find_command = { "fd", "--type", "file", "--hidden", "--no-ignore", "--strip-cwd-prefix" },
  })
end

-- find all files, it includes hidden, ignored by .gitignore and ~/.config/fd/ignore but exclude node_modules
-- The 99% of the time node_modules are not relevant!
local function find_files()
  require("telescope.builtin").find_files({
    find_command = {
      "fd",
      "--type",
      "file",
      "--hidden",
      "--no-ignore",
      "--strip-cwd-prefix",
      "--exclude",
      "node_modules",
    },
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
  require("telescope").extensions.file_browser.file_browser({ path = "%:p:h", hidden = true, respect_gitignore = false })
end

local function git_worktrees()
  require("telescope").extensions.git_worktree.git_worktrees()
end

local function live_grep()
  -- check if this idea!
  -- create telescope_custom_pickers in ariel folder
  -- https://github.com/JoosepAlviste/dotfiles/blob/master/config/nvim/lua/j/plugins/telescope.lua#L75
  require("telescope").extensions.live_grep_args.live_grep_args()
end

return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-fzy-native.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
    "nvim-telescope/telescope-live-grep-args.nvim",
    "ThePrimeagen/git-worktree.nvim",
    {
      "AckslD/nvim-neoclip.lua",
      config = function()
        require("neoclip").setup()
      end,
    },
  },
  event = { "VeryLazy" },
  keys = {
    { "<leader>t", ":Telescope<CR>", desc = "open telescope overwiew" },
    { "<leader>fp", project_files, desc = "list git files respecting .gitignore" },
    {
      "<leader>ff",
      find_files,
      desc = "list files in the current working directory (excludes node_modules)",
    },
    {
      "<leader>fa",
      find_all_files,
      desc = "list files in the current working directory (includes node_modules)",
    },
    { "<leader>f.", find_dotfiles, desc = "list dotfiles" },
    { "<leader>fb", ":Telescope buffers<CR>", desc = "list open buffers" },
    { "<leader>fd", ":Telescope diagnostics<CR>", desc = "list diagnostics" },
    {
      "<leader>e",
      explore_files,
      desc = "explore files in the folder of the active buffer",
    },
    {
      "<leader>fs",
      live_grep,
      desc = "[f]ind [s]tring across current working directory",
    },
    { "<leader>fl", ":Telescope current_buffer_fuzzy_find<CR>", desc = "search active buffer line" },
    { "<leader>fh", ":Telescope help_tags<CR>", desc = "list help entries" },
    { "<leader>fc", ":Telescope colorscheme<CR>", desc = "list theme entries" },
    { "<leader>fk", ":Telescope keymaps<CR>", desc = "list keymaps" },
    { "<leader>gcc", ":Telescope git_commits<CR>", desc = "list commits" },
    { "<leader>gcb", ":Telescope git_bcommits<CR>", desc = "list commits that changed the active buffer" },
    { "<leader>gb", ":Telescope git_branches<CR>", desc = "list branches" },
    { "<leader>fy", ":Telescope neoclip<CR>", desc = "find yanked text over time" },
    { "<leader>gw", git_worktrees, desc = "list git worktrees" },
  },
  config = function()
    local telescope = require("telescope")
    local sorters = require("telescope.sorters")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local actions_layout = require("telescope.actions.layout")
    local lga_actions = require("telescope-live-grep-args.actions")

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
        live_grep_args = {
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
            "-g",
            "!package-lock.json",
            "-g",
            "!yarn.lock",
          },
          auto_quoting = true, -- enable/disable auto-quoting
          -- define mappings, e.g.
          mappings = { -- extend mappings
            i = {
              ["<C-k>"] = lga_actions.quote_prompt(),
              ["<C-i>"] = lga_actions.quote_prompt({ postfix = " --iglob " }),
            },
          },
        },
      },
      pickers = {
        git_commits = {
          mappings = {
            i = {
              ["<CR>"] = function(prompt_bufnr)
                -- get the selected file name
                local commit_sha = require("telescope.actions.state").get_selected_entry().value
                -- close telescope
                require("telescope.actions").close(prompt_bufnr)
                -- open diffview with the commit changes agains the previous commit
                vim.cmd("DiffviewOpen " .. commit_sha .. "~1.." .. commit_sha)
              end,
            },
          },
        },
        git_branches = {
          mappings = {
            i = {
              ["<CR>"] = function(prompt_bufnr)
                -- get the selected file name
                local branch_name = require("telescope.actions.state").get_selected_entry().value
                -- close telescope
                require("telescope.actions").close(prompt_bufnr)
                -- open diffview with the changes between the selected branch and the main branch
                vim.cmd("DiffviewOpen " .. "main.." .. branch_name)
              end,
            },
          },
        },
      },
    })

    -- extensions
    telescope.load_extension("fzy_native")
    telescope.load_extension("file_browser")
    telescope.load_extension("neoclip")
    telescope.load_extension("live_grep_args")
    telescope.load_extension("git_worktree")
  end,
}
