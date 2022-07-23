local tu = require("user.plugins.telescope")
local tb = require("telescope.builtin")
local te = require("telescope").extensions

-- set <leader> key to space (default is '\')
vim.g.mapleader = " "

vim.keymap.set("n", "<leader><CR>", require("user.core.utils").reload_config, { desc = "reload neovim config" })
vim.keymap.set("n", "<C-f>", ":silent !tmux new-window tmux-sessionizer<CR>", { desc = "create tmux session" })
vim.keymap.set("n", "<C-s>", ":silent !tmux new-window tmux-find-session<CR>", { desc = "find tmux session" })
vim.keymap.set("n", "<leader>x", ":silent !chmod +x %<CR>", { desc = "make current buffer executable" })
vim.keymap.set("n", "<leader>/", ":nohlsearch<CR>", { desc = "clear highlighed search" })
vim.keymap.set("n", "<leader>w", ":w!<CR>", { desc = "save current buffer" })
vim.keymap.set("n", "<leader>W", ":wa!<CR>", { desc = "save all open buffers" })
vim.keymap.set("n", "<leader>n", ":enew<CR>", { desc = "create new buffer" })
vim.keymap.set("n", "<leader><leader>", ":bd<CR>", { desc = "close current buffer" })
vim.keymap.set("n", "<leader>1", ":set bg=dark<CR>", { desc = "set dark mode" })
vim.keymap.set("n", "<leader>2", ":set bg=light<CR>", { desc = "set light mode" })
vim.keymap.set("n", "<leader>|", ":vsplit<CR>", { desc = "create vertical split" })
vim.keymap.set("n", "<leader>-", ":split<CR>", { desc = "create horizontal split" })
-- telescope
vim.keymap.set("n", "<leader>t", ":Telescope<CR>", { desc = "open telescope overwiew" })
vim.keymap.set("n", "<leader>p", tu.project_files, { desc = "list git files respecting .gitignore" })
vim.keymap.set("n", "<leader>f", tu.find_files, { desc = "list files in the current working directory" })
vim.keymap.set("n", "<leader>b", tb.buffers, { desc = "list open buffers" })
vim.keymap.set("n", "<leader>e", tu.explore_files, { desc = "explore files in the folder of the active buffer" })
vim.keymap.set("n", "<leader>s", tu.live_grep, { desc = "search across current working directory" })
vim.keymap.set("n", "<leader>l", tb.current_buffer_fuzzy_find, { desc = "search active buffer line" })
vim.keymap.set("n", "<leader>h", tb.help_tags, { desc = "list help entries" })
vim.keymap.set("n", "<leader>k", tb.keymaps, { desc = "list keymaps" })
-- git
vim.keymap.set("n", "<leader>gc", tu.git_commits, { desc = "list commits" })
vim.keymap.set("n", "<leader>gb", tu.git_bcommits, { desc = "list commits that changed the actuve buffer" })
vim.keymap.set("n", "<leader>gw", te.git_worktree.git_worktrees, { desc = "list git worktrees" })
-- quickfix list navigation
vim.keymap.set("n", "[q", ":cprev<CR>", { desc = "quickfix list previous item" })
vim.keymap.set("n", "[Q", ":cfirst<CR>", { desc = "quickfix list first item" })
vim.keymap.set("n", "]q", ":cnext<CR>", { desc = "quickfix list next item" })
vim.keymap.set("n", "]Q", ":clast<CR>", { desc = "quickfix list last item" })
vim.keymap.set("n", "<leader>[", ":copen<CR>", { desc = "open quickfix list" })
vim.keymap.set("n", "<leader>]", ":cclose<CR>", { desc = "close quickfix list" })
-- location list navigation
-- The location list behaves just like the quickfix list except that it is local to the current window instead of being global to the Vim session.
-- So if you have five open windows, you can have up to five location lists, but only one quickfix list.
-- disable for know due it collides with paragraph navigation
-- vim.keymap.set("n", "{q", ":lprev<CR>", { desc = "" })
-- vim.keymap.set("n", "{Q", ":lfirst<CR>", { desc = "" })
-- vim.keymap.set("n", "}q", ":lnext<CR>", { desc = "" })
-- vim.keymap.set("n", "}Q", ":llast<CR>", { desc = "" })
-- vim.keymap.set("n", "<leader>{", ":lopen<CR>", { desc = "" })
-- vim.keymap.set("n", "<leader>}", ":lclose<CR>", { desc = "" })
-- move lines and selected blocks
vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "move current line down" })
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "move current line up" })
vim.keymap.set("i", "<A-j>", "<ESC>:m .+1<CR>==gi", { desc = "move current line down" })
vim.keymap.set("i", "<A-k>", "<ESC>:m .-2<CR>==gi", { desc = "move current line up" })
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "move current line down" })
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "move current line up" })
