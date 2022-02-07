local keymap = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

-- set <leader> key to space (default is '\')
vim.g.mapleader = ' '

-- modes 
--  normal = 'n'
--  insert = 'i'
--  visual = 'v'
--  visual_block = 'x'
--  term = 't'
--  command = 'c'

-- reload vim config
keymap('n', '<leader><CR>', ':ReloadConfig<CR>', opts)

-- make current buffer executable
keymap('n', '<leader>x', ':silent !chmod +x %<CR>', opts)

-- quickfix list navigation
keymap('n', '<C-j>', ':cnext<CR>', opts)
keymap('n', '<C-k>', ':cprev<CR>', opts)

-- open netrw explorer (pv -> project view)
keymap('n', '<leader>pv', ':Ex<CR>', opts)

-- save current buffer
keymap('n', '<leader>ss', ':w!<CR>', opts)
-- save all open buffers
keymap('n', '<leader>sa', ':wa!<CR>', opts)

-- create vertical and horizontal splits
keymap('n', '<leader>v', ':vsplit<CR>', opts)
keymap('n', '<leader>h', ':split<CR>', opts)

-- telescope
keymap('n', '<leader>ff',  ":lua require('user.plugins.telescope').find_files()<CR>", opts)
keymap('n', '<leader>fg',  ":lua require('user.plugins.telescope').live_grep()<CR>", opts)
keymap('n', '<leader>fb',  ":lua require('telescope.builtin').buffers()<CR>", opts)
keymap('n', '<leader>fh',  ":lua require('telescope.builtin').help_tags()<CR>", opts)
keymap('n', '<leader>gf',  ":lua require('telescope.builtin').git_files()<CR>", opts)
keymap('n', '<leader>gb',  ":lua require('telescope.builtin').git_branches()<CR>", opts)
keymap('n', '<leader>gw',  ":lua require('telescope').extensions.git_worktree.git_worktrees()<CR>", opts)
keymap('n', '<leader>bf',  ":lua require('telescope').extensions.file_browser.file_browser()<CR>", opts)
keymap('n', '<leader>.',  ":lua require('user.plugins.telescope').find_dotfiles()<CR>", opts)


-- move lines and selected blocks
keymap('n', '<A-j>', ':m .+1<CR>==', opts)
keymap('n', '<A-k>', ':m .-2<CR>==', opts)

keymap('i', '<A-j>', '<ESC>:m .+1<CR>==gi', opts)
keymap('i', '<A-k>', '<ESC>:m .-2<CR>==gi', opts)

keymap('v', '<A-j>', ":m '>+1<CR>gv=gv", opts)
keymap('v', '<A-k>', ":m '<-2<CR>gv=gv", opts)
