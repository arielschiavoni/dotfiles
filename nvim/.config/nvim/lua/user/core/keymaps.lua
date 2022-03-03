local keymap = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

-- set <leader> key to space (default is '\')
vim.g.mapleader = " "

-- modes
--  normal = 'n'
--  insert = 'i'
--  visual = 'v'
--  visual_block = 'x'
--  term = 't'
--  command = 'c'

-- reload vim config
keymap("n", "<leader><CR>", ":ReloadConfig<CR>", opts)

-- make current buffer executable
keymap("n", "<leader>x", ":silent !chmod +x %<CR>", opts)

-- clear highlighed search
keymap("n", "<leader>/", ":nohlsearch<CR>", opts)

-- quickfix list navigation
keymap("n", "<C-j>", ":cnext<CR>", opts)
keymap("n", "<C-k>", ":cprev<CR>", opts)
keymap("n", "<leader>qo", ":copen<CR>", opts)
keymap("n", "<leader>qc", ":cclose<CR>", opts)

-- open netrw explorer
keymap("n", "<leader>t", ":Ex<CR>", opts)

-- save current buffer
keymap("n", "<leader>s", ":w!<CR>", opts)
-- save all open buffers
keymap("n", "<leader>a", ":wa!<CR>", opts)

-- create vertical and horizontal splits
keymap("n", "<leader>|", ":vsplit<CR>", opts)
keymap("n", "<leader>-", ":split<CR>", opts)

-- telescope
keymap("n", "<leader>p", ":lua require('user.plugins.telescope').find_files()<CR>", opts)
keymap("n", "<leader>f", ":lua require('user.plugins.telescope').live_grep()<CR>", opts)
keymap("n", "<leader>b", ":lua require('telescope.builtin').buffers()<CR>", opts)
keymap("n", "<leader>l", ":lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>", opts)
keymap("n", "<leader>h", ":lua require('telescope.builtin').help_tags()<CR>", opts)
keymap("n", "<leader>k", ":lua require('telescope.builtin').keymaps()<CR>", opts)
keymap("n", "<leader>gf", ":lua require('telescope.builtin').git_files()<CR>", opts)
keymap("n", "<leader>gb", ":lua require('telescope.builtin').git_branches()<CR>", opts)
keymap("n", "<leader>gh", ":0Gclog<CR>", opts)
keymap("n", "<leader>wl", ":lua require('telescope').extensions.git_worktree.git_worktrees()<CR>", opts)
keymap("n", "<leader>wc", ":lua require('telescope').extensions.git_worktree.create_git_worktree()<CR>", opts)
keymap("n", "<leader>e", ":lua require('telescope').extensions.file_browser.file_browser()<CR>", opts)
keymap("n", "<leader>.", ":lua require('user.plugins.telescope').find_dotfiles()<CR>", opts)

-- move lines and selected blocks
keymap("n", "<A-j>", ":m .+1<CR>==", opts)
keymap("n", "<A-k>", ":m .-2<CR>==", opts)

keymap("i", "<A-j>", "<ESC>:m .+1<CR>==gi", opts)
keymap("i", "<A-k>", "<ESC>:m .-2<CR>==gi", opts)

keymap("v", "<A-j>", ":m '>+1<CR>gv=gv", opts)
keymap("v", "<A-k>", ":m '<-2<CR>gv=gv", opts)
