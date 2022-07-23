local tu = require("user.plugins.telescope")
local tb = require("telescope.builtin")
local te = require("telescope").extensions

-- set <leader> key to space (default is '\')
vim.g.mapleader = " "

vim.keymap.set("n", "<leader><CR>", require("user.core.utils").reload_config, { desc = "reload neovim config" }) -- create tmux session
vim.keymap.set("n", "<C-f>", ":silent !tmux new-window tmux-sessionizer<CR>", { desc = "create tmux session" }) -- find and switch to tmux session
vim.keymap.set("n", "<C-s>", ":silent !tmux new-window tmux-find-session<CR>") -- make current buffer executable
vim.keymap.set("n", "<leader>x", ":silent !chmod +x %<CR>")
vim.keymap.set("n", "<leader>/", ":nohlsearch<CR>") -- clear highlighed search
vim.keymap.set("n", "<leader>w", ":w!<CR>") -- save current buffer
vim.keymap.set("n", "<leader>W", ":wa!<CR>") -- save all open buffers
vim.keymap.set("n", "<leader>n", ":enew<CR>") -- create new buffer
vim.keymap.set("n", "<leader><leader>", ":bd<CR>") -- close current buffer
vim.keymap.set("n", "<leader>1", ":set bg=dark<CR>")
vim.keymap.set("n", "<leader>2", ":set bg=light<CR>")
vim.keymap.set("n", "<leader>|", ":vsplit<CR>") -- create vertical and horizontal splits
vim.keymap.set("n", "<leader>-", ":split<CR>")
-- telescope
vim.keymap.set("n", "<leader>t", ":Telescope<CR>")
vim.keymap.set("n", "<leader>p", tu.project_files)
vim.keymap.set("n", "<leader>f", tu.live_grep)
vim.keymap.set("n", "<leader>b", tb.buffers)
vim.keymap.set("n", "<leader>l", tb.current_buffer_fuzzy_find)
vim.keymap.set("n", "<leader>h", tb.help_tags)
vim.keymap.set("n", "<leader>k", tb.keymaps)
vim.keymap.set("n", "<leader>e", tu.explore_files, { desc = "explore files in the curent folder" })
-- git
vim.keymap.set("n", "<leader>gc", tu.git_commits, { desc = "lists commits" })
vim.keymap.set("n", "<leader>gb", tu.git_bcommits, { desc = "lists commits that changed the current buffer" })
vim.keymap.set("n", "<leader>gw", te.git_worktree.git_worktrees, { desc = "list git work trees" })
vim.keymap.set("n", "<leader>gi", tu.find_files, { desc = "lists files including git ignored one" })

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

-- move lines and selected blocks
vim.keymap.set("n", "<A-j>", ":m .+1<CR>==")
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==")

vim.keymap.set("i", "<A-j>", "<ESC>:m .+1<CR>==gi")
vim.keymap.set("i", "<A-k>", "<ESC>:m .-2<CR>==gi")

vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv")
