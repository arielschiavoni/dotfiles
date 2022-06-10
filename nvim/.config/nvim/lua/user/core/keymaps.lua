-- set <leader> key to space (default is '\')
vim.g.mapleader = " "

-- reload vim config
vim.keymap.set("n", "<leader><CR>", require("user.core.utils").reload_config)

-- create tmux session
vim.keymap.set("n", "<C-f>", ":silent !tmux new-window tmux-sessionizer<CR>")
-- find and switch to tmux session
vim.keymap.set("n", "<C-s>", ":silent !tmux new-window tmux-find-session<CR>")

-- make current buffer executable
vim.keymap.set("n", "<leader>x", ":silent !chmod +x %<CR>")

-- clear highlighed search
vim.keymap.set("n", "<leader>/", ":nohlsearch<CR>")

-- quickfix list navigation
vim.keymap.set("n", "[q", ":cprev<CR>")
vim.keymap.set("n", "[Q", ":cfirst<CR>")
vim.keymap.set("n", "]q", ":cnext<CR>")
vim.keymap.set("n", "]Q", ":clast<CR>")
vim.keymap.set("n", "<leader>[", ":copen<CR>")
vim.keymap.set("n", "<leader>]", ":cclose<CR>")

-- location list navigation
-- The location list behaves just like the quickfix list except that it is local to the current window instead of being global to the Vim session.
-- So if you have five open windows, you can have up to five location lists, but only one quickfix list.
-- disable for know due it collides with paragraph navigation
-- vim.keymap.set("n", "{q", ":lprev<CR>")
-- vim.keymap.set("n", "{Q", ":lfirst<CR>")
-- vim.keymap.set("n", "}q", ":lnext<CR>")
-- vim.keymap.set("n", "}Q", ":llast<CR>")
-- vim.keymap.set("n", "<leader>{", ":lopen<CR>")
-- vim.keymap.set("n", "<leader>}", ":lclose<CR>")

-- open netrw explorer
vim.keymap.set("n", "<leader>t", ":Ex<CR>")
-- save current buffer
vim.keymap.set("n", "<leader>s", ":w!<CR>")
-- save all open buffers
vim.keymap.set("n", "<leader>a", ":wa!<CR>")
-- create new buffer
vim.keymap.set("n", "<leader>n", ":enew<CR>")
-- close current buffer
vim.keymap.set("n", "<leader><leader>", ":bd<CR>")
vim.keymap.set("n", "<leader>1", ":set bg=dark<CR>")
vim.keymap.set("n", "<leader>2", ":set bg=light<CR>")

-- create vertical and horizontal splits
vim.keymap.set("n", "<leader>|", ":vsplit<CR>")
vim.keymap.set("n", "<leader>-", ":split<CR>")

-- telescope
local tu = require("user.plugins.telescope")
local tb = require("telescope.builtin")
local te = require("telescope").extensions

vim.keymap.set("n", "<leader>p", tu.find_files)
vim.keymap.set("n", "<leader>f", tu.live_grep)
vim.keymap.set("n", "<leader>b", tb.buffers)
vim.keymap.set("n", "<leader>l", tb.current_buffer_fuzzy_find)
vim.keymap.set("n", "<leader>h", tb.help_tags)
vim.keymap.set("n", "<leader>k", tb.keymaps)
vim.keymap.set("n", "<leader>gf", tb.git_files)
vim.keymap.set("n", "<leader>gb", tb.git_branches)
-- show current file git history
vim.keymap.set("n", "<leader>gh", ":0Gclog<CR>")
-- open fugitive git status buffer
vim.keymap.set("n", "<leader>gs", ":G<CR>")
-- resolve git conflict taking the left side
vim.keymap.set("n", "<leader>g[", ":diffget //3<CR>")
-- resolve git conflict taking the right side
vim.keymap.set("n", "<leader>g]", ":diffget //2<CR>")
vim.keymap.set("n", "<leader>gp", ":Gpush<CR>")
vim.keymap.set("n", "<leader>gl", ":Gclog<CR>")
vim.keymap.set("n", "<leader>wl", te.git_worktree.git_worktrees)
vim.keymap.set("n", "<leader>wc", te.git_worktree.create_git_worktree)
vim.keymap.set("n", "<leader>e", te.file_browser.file_browser)
vim.keymap.set("n", "<leader>.", tu.find_dotfiles)

-- move lines and selected blocks
vim.keymap.set("n", "<A-j>", ":m .+1<CR>==")
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==")

vim.keymap.set("i", "<A-j>", "<ESC>:m .+1<CR>==gi")
vim.keymap.set("i", "<A-k>", "<ESC>:m .-2<CR>==gi")

vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv")
