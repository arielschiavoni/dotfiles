local telescope = require("telescope")
local builtin = require("telescope.builtin")
local file_browser = telescope.extensions.file_browser
local telescope_snippets = require("ariel.telescope_snippets")
local utils = require("ariel.utils")

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

local git_log_format = "--format=%h %as %an %s"

M.git_commits = function(opts)
  -- https://git-scm.com/docs/pretty-formats
  opts = opts
    or {
      -- adjust the original git command to show the date of the commit
      git_command = {
        "git",
        "log",
        git_log_format,
      },
    }
  builtin.git_commits(opts)
end

-- list commits that containing the previously selected text
M.git_scommits = function(opts)
  opts = opts
    or {
      -- adjust the original git command to show the date of the commit
      git_command = {
        "git",
        "log",
        git_log_format,
        "-S",
        utils.get_visual_selection(),
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
        git_log_format,
        "--",
        "%", -- commits that changed the current buffer -> %
      },
    }
  builtin.git_bcommits(opts)
end

M.snippets = function(opts)
  opts = opts or {}
  telescope_snippets.snippets(opts)
end

return M
