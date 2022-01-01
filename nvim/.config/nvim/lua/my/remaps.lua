local utils = require("my.utils")
local create_remap = utils.create_remap

-- set <leader> key to space (default is "\")
vim.g.mapleader = " "

-- reload vim config
create_remap("n", "<leader><CR>", "<cmd> ReloadConfig<CR>")

-- quickfix list navigation
create_remap("n", "<C-j>", ":cnext<CR>")
create_remap("n", "<C-k>", ":cprev<CR>")

-- Vexplore (netrw vertical split and explore)
create_remap("n", "<leader>pv", ":Vex<CR>")

-- save current buffer
create_remap("n", "<leader>ss", ":w!<CR>")
-- save all open buffers
create_remap("n", "<leader>sa", ":wa!<CR>")

-- create vertical and horizontal splits
create_remap("n", "<leader>v", ":vsplit<CR>")
create_remap("n", "<leader>h", ":split<CR>")

-- telescope
create_remap('n', '<leader>ff',  "<cmd> lua require('my.plugins.telescope').find_files()<CR>")
create_remap('n', '<leader>fg',  "<cmd> lua require('my.plugins.telescope').live_grep()<CR>")
create_remap('n', '<leader>fb',  "<cmd> lua require('telescope.builtin').buffers()<CR>")
create_remap('n', '<leader>fh',  "<cmd> lua require('telescope.builtin').help_tags()<CR>")
create_remap('n', '<leader>gf',  "<cmd> lua require('telescope.builtin').git_files()<CR>")
create_remap('n', '<leader>gb',  "<cmd> lua require('telescope.builtin').git_branches()<CR>")
create_remap('n', '<leader>bf',  "<cmd> lua require('telescope').extensions.file_browser.file_browser()<CR>")
create_remap('n', '<leader>.',  "<cmd> lua require('my.plugins.telescope').find_dotfiles()<CR>")
