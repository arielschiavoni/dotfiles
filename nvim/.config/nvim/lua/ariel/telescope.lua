local telescope = require("telescope")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local actions_layout = require("telescope.actions.layout")
local builtin = require("telescope.builtin")
local file_browser = telescope.extensions.file_browser
local telescope_snippets = require("ariel.telescope_snippets")
local get_visual_selection = require("ariel.utils")

telescope.setup({
  defaults = {
    -- layout_strategy = "vertical",
    -- layout_config = {
    --   vertical = { width = 0.8 },
    --   -- other layout configuration here
    -- },
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
  -- pickers = {
  --   find_files = {
  --     theme = "dropdown",
  --   },
  -- },
  extensions = {
    fzy_native = {
      override_generic_sorter = false,
      override_file_sorter = true,
    },
  },
})

-- This will load fzy_native and have it override the default file sorter
telescope.load_extension("fzy_native")
telescope.load_extension("file_browser")
-- Setup telescope to use the ThePrimeagen/git-worktree.nvim extension
telescope.load_extension("git_worktree")
telescope.load_extension("harpoon")

-- extends telescope with more funtions exported from this module
local M = {}

M.find_dotfiles = function()
  builtin.git_files({
    prompt_title = "< dotfiles >",
    cwd = vim.env.DOTFILES,
  })
end

-- find all files, including hidden and ignored by .gitignore
-- node_modules are globally ignored in ~/.config/fd/ignore
M.find_files = function()
  builtin.find_files({
    find_command = { "fd", "--type", "file", "--hidden", "--no-ignore-vcs", "--strip-cwd-prefix" },
  })
end

-- try to find files with git and if not found then fallback to find_files :-)
M.project_files = function()
  local ok = pcall(builtin.git_files, { show_untracked = true })
  if not ok then
    M.find_files()
  end
end

M.explore_files = function()
  file_browser.file_browser({ path = "%:p:h" })
end

M.live_grep = function()
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

M.git_commits = function(opts)
  -- https://git-scm.com/docs/pretty-formats
  opts = opts
    or {
      -- adjust the original git command to show the date of the commit
      git_command = {
        "git",
        "log",
        "--format=%h %as %an %s", -- show data & author name
        "--",
        ".",
      },
    }
  builtin.git_commits(opts)
end

M.git_bcommits = function(opts)
  opts = opts
    or {
      git_command = {
        "git",
        "log",
        -- "--format=%h %as %<(7,trunc)%an %s",
        "--format=%h %as %an %s", -- show data & author name
        "--",
        "%",
      },
    }
  builtin.git_bcommits(opts)
end

M.snippets = function(opts)
  opts = opts or {}
  telescope_snippets.snippets(opts)
end

return M
