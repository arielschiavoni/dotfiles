local utils = require("ariel.utils")
local create_remap = utils.create_remap

-- set <leader> key to space (default is "\")
vim.g.mapleader = " "

-- reload vim config
create_remap("n", "<leader><CR>", ":so ~/.config/nvim/init.lua<CR>")

-- quickfix list navigation
create_remap("n", "<C-j>", ":cnext<CR>")
create_remap("n", "<C-k>", ":cprev<CR>")

-- Vexplore (netrw vertical split and explore)
create_remap("n", "<leader>pv", ":Vex<CR>")

-- save files with ctrl-s
create_remap("n", "<leader>s", ":w!<CR>")

-- create vertical and horizontal splits
create_remap("n", "<leader>v", ":vsplit<CR>")
create_remap("n", "<leader>h", ":split<CR>")

-- telescope
create_remap('n', '<leader>ff',  "<cmd> lua require('telescope.builtin').find_files()<CR>")
create_remap('n', '<leader>fg',  "<cmd> lua require('telescope.builtin').live_grep()<CR>")
create_remap('n', '<leader>fb',  "<cmd> lua require('telescope.builtin').buffers()<CR>")
create_remap('n', '<leader>fh',  "<cmd> lua require('telescope.builtin').help_tags()<CR>")
create_remap('n', '<leader>gf',  "<cmd> lua require('telescope.builtin').git_files()<CR>")
create_remap('n', '<leader>gb',  "<cmd> lua require('telescope.builtin').git_branches()<CR>")
create_remap('n', '<leader>vrc',  "<cmd> lua require('ariel.plugins.telescope').search_dotfiles({ hidden = true })<CR>")
