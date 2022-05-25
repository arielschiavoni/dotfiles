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

-- create tmux session
keymap("n", "<C-f>", ":silent !tmux new-window tmux-sessionizer<CR>", opts)
-- find and switch to tmux session
keymap("n", "<C-s>", ":silent !tmux new-window tmux-find-session<CR>", opts)

-- make current buffer executable
keymap("n", "<leader>x", ":silent !chmod +x %<CR>", opts)

-- clear highlighed search
keymap("n", "<leader>/", ":nohlsearch<CR>", opts)

-- quickfix list navigation
keymap("n", "[q", ":cprev<CR>", opts)
keymap("n", "[Q", ":cfirst<CR>", opts)
keymap("n", "]q", ":cnext<CR>", opts)
keymap("n", "]Q", ":clast<CR>", opts)
keymap("n", "<leader>[", ":copen<CR>", opts)
keymap("n", "<leader>]", ":cclose<CR>", opts)

-- location list navigation
-- The location list behaves just like the quickfix list except that it is local to the current window instead of being global to the Vim session.
-- So if you have five open windows, you can have up to five location lists, but only one quickfix list.
-- disable for know due it collides with paragraph navigation
-- keymap("n", "{q", ":lprev<CR>", opts)
-- keymap("n", "{Q", ":lfirst<CR>", opts)
-- keymap("n", "}q", ":lnext<CR>", opts)
-- keymap("n", "}Q", ":llast<CR>", opts)
-- keymap("n", "<leader>{", ":lopen<CR>", opts)
-- keymap("n", "<leader>}", ":lclose<CR>", opts)

-- open netrw explorer
keymap("n", "<leader>t", ":Ex<CR>", opts)
-- save current buffer
keymap("n", "<leader>s", ":w!<CR>", opts)
-- save all open buffers
keymap("n", "<leader>a", ":wa!<CR>", opts)
-- create new buffer
keymap("n", "<leader>n", ":enew<CR>", opts)
-- close current buffer
keymap("n", "<leader><leader>", ":bd<CR>", opts)
keymap("n", "<leader>1", ":set bg=dark<CR>", opts)
keymap("n", "<leader>2", ":set bg=light<CR>", opts)

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
-- show current file git history
keymap("n", "<leader>gh", ":0Gclog<CR>", opts)
-- open fugitive git status buffer
keymap("n", "<leader>gs", ":G<CR>", opts)
-- resolve git conflict taking the left side
keymap("n", "<leader>g[", ":diffget //3<CR>", opts)
-- resolve git conflict taking the right side
keymap("n", "<leader>g]", ":diffget //2<CR>", opts)
keymap("n", "<leader>gp", ":Gpush<CR>", opts)
keymap("n", "<leader>gl", ":Gclog<CR>", opts)
keymap("n", "<leader>wl", ":lua require('telescope').extensions.git_worktree.git_worktrees()<CR>", opts)
keymap("n", "<leader>wc", ":lua require('telescope').extensions.git_worktree.create_git_worktree()<CR>", opts)
keymap("n", "<leader>e", ":lua require('telescope').extensions.file_browser.file_browser()<CR>", opts)
keymap("n", "<leader>.", ":lua require('user.plugins.telescope').find_dotfiles()<CR>", opts)

keymap("n", "<F5>", ":lua require('dap').continue()<CR>", opts)
keymap("n", "<F10>", ":lua require('dap').step_over()<CR>", opts)
keymap("n", "<F11>", ":lua require('dap').step_into()<CR>", opts)
keymap("n", "<F12>", ":lua require('dap').step_out()<CR>", opts)
keymap("n", "<leader>db", ":lua require('dap').toggle_breakpoint()<CR>", opts)
keymap("n", "<leader>dB", ":lua require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>", opts)
-- keymap("n", "<leader>lp", ":lua require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: '))<CR>", opts)
keymap("n", "<leader>dr", ":lua require('dap').repl.open()<CR>", opts)
keymap("n", "<leader>dl", ":lua require('dap').run_last()<CR>", opts)

-- move lines and selected blocks
keymap("n", "<A-j>", ":m .+1<CR>==", opts)
keymap("n", "<A-k>", ":m .-2<CR>==", opts)

keymap("i", "<A-j>", "<ESC>:m .+1<CR>==gi", opts)
keymap("i", "<A-k>", "<ESC>:m .-2<CR>==gi", opts)

keymap("v", "<A-j>", ":m '>+1<CR>gv=gv", opts)
keymap("v", "<A-k>", ":m '<-2<CR>gv=gv", opts)
