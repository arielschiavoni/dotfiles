local telescope = require("telescope")
local builtin = require("telescope.builtin")
local file_browser = telescope.extensions.file_browser
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

local git_log_format = "--pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %Cgreen%as %C(bold blue)<%an>%Creset %s'"

M.git_commits = function(opts)
  -- https://git-scm.com/docs/pretty-formats
  opts = opts
    or {
      -- disabled for now because telescope does not format the text properly
      -- git_command = { "git", "log", "--graph", "--oneline", "--decorate", git_log_format, "--", "." },
      git_command = { "git", "log", "--graph", "--oneline", "--decorate", "--", "." },
    }
  builtin.git_commits(opts)
end

M.git_scommits = function(opts)
  opts = opts
    or {
      -- list commits containing the previously selected text
      git_command = { "git", "log", "--graph", "--oneline", "--decorate", "-S", utils.get_visual_selection() },
    }
  builtin.git_commits(opts)
end

M.git_bcommits = function(opts)
  opts = opts
    or {
      -- commits that changed the current buffer -> %
      git_command = { "git", "log", "--graph", "--oneline", "--decorate", "--", "%" },
    }
  builtin.git_bcommits(opts)
end

return M
