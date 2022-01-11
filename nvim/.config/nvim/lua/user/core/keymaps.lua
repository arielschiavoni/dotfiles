
local keymap = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

-- set <leader> key to space (default is '\')
vim.g.mapleader = ' '

-- reload vim config
keymap('n', '<leader><CR>', '<cmd> ReloadConfig<CR>', opts)

-- quickfix list navigation
keymap('n', '<C-j>', ':cnext<CR>', opts)
keymap('n', '<C-k>', ':cprev<CR>', opts)

-- Vexplore (netrw vertical split and explore)
keymap('n', '<leader>pv', ':Vex<CR>', opts)

-- save current buffer
keymap('n', '<leader>ss', ':w!<CR>', opts)
-- save all open buffers
keymap('n', '<leader>sa', ':wa!<CR>', opts)

-- create vertical and horizontal splits
keymap('n', '<leader>v', ':vsplit<CR>', opts)
keymap('n', '<leader>h', ':split<CR>', opts)

-- telescope
keymap('n', '<leader>ff',  "<cmd> lua require('user.plugins.telescope').find_files()<CR>", opts)
keymap('n', '<leader>fg',  "<cmd> lua require('user.plugins.telescope').live_grep()<CR>", opts)
keymap('n', '<leader>fb',  "<cmd> lua require('telescope.builtin').buffers()<CR>", opts)
keymap('n', '<leader>fh',  "<cmd> lua require('telescope.builtin').help_tags()<CR>", opts)
keymap('n', '<leader>gf',  "<cmd> lua require('telescope.builtin').git_files()<CR>", opts)
keymap('n', '<leader>gb',  "<cmd> lua require('telescope.builtin').git_branches()<CR>", opts)
keymap('n', '<leader>bf',  "<cmd> lua require('telescope').extensions.file_browser.file_browser()<CR>", opts)
keymap('n', '<leader>.',  "<cmd> lua require('user.plugins.telescope').find_dotfiles()<CR>", opts)
