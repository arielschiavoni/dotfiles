local utils = require("ariel.utils")
local telescope = require("ariel.telescope")
local telescope_builtin = require("telescope.builtin")
local telescope_extensions = require("telescope").extensions
local Remap = require("ariel.keymap")
local nnoremap = Remap.nnoremap
local inoremap = Remap.inoremap
local vnoremap = Remap.vnoremap

nnoremap("<leader><CR>", utils.reload_config, { desc = "reload neovim config" })
nnoremap("<C-f>", ":silent !tmux new-window tmux-sessionizer<CR>", { desc = "create tmux session" })
nnoremap("<C-s>", ":silent !tmux new-window tmux-find-session<CR>", { desc = "find tmux session" })
nnoremap("<leader>x", ":silent !chmod +x %<CR>", { desc = "make current buffer executable" })
nnoremap("<leader>/", ":nohlsearch<CR>", { desc = "clear highlighed search" })
nnoremap("<leader>w", ":w!<CR>", { desc = "save current buffer" })
nnoremap("<leader>W", ":wa!<CR>", { desc = "save all open buffers" })
nnoremap("<leader>n", ":enew<CR>", { desc = "create new buffer" })
nnoremap("<leader><leader>", ":bd<CR>", { desc = "close current buffer" })
nnoremap("<leader>^", utils.toggle_background, { desc = "set dark mode" })
nnoremap("<leader>|", ":vsplit<CR>", { desc = "create vertical split" })
nnoremap("<leader>-", ":split<CR>", { desc = "create horizontal split" })
nnoremap("<leader>~", ":let @* = expand('%:p')<CR>", { desc = "copy buffer's absolute path to clipboard" })
nnoremap("<leader>`", ":let @* = expand('%:t')<CR>", { desc = "copy buffer's file name to clipboard" })
nnoremap("<leader>O", "m`O<Esc>``", { desc = "insert empty line above without leaving cursor position" })
nnoremap("<leader>o", "m`o<Esc>``", { desc = "insert empty line below without leaving cursor position" })
nnoremap("<F11>", ":set spell!<CR>", { desc = "enable spell checking", silent = true })
-- nnoremap("<leader>z", '"_dP', { desc = "allows to paste text without afecting the unnamed registry" })

-- next greatest remap ever : asbjornHaland
-- nnoremap("<leader>y", '"+y')
-- vnoremap("<leader>y", '"+y')
-- nmap("<leader>Y", '"+Y')
--
-- nnoremap("<leader>d", '"_d')
-- vnoremap("<leader>d", '"_d')
--
-- vnoremap("<leader>d", '"_d')
-- telescope
nnoremap("<leader>t", ":Telescope<CR>", { desc = "open telescope overwiew" })
nnoremap("<leader>p", telescope.project_files, { desc = "list git files respecting .gitignore" })
nnoremap("<leader>f", telescope.find_files, { desc = "list files in the current working directory" })
nnoremap("<leader>.", telescope.find_dotfiles, { desc = "list dotfiles" })
nnoremap("<leader>b", telescope_builtin.buffers, { desc = "list open buffers" })
nnoremap("<leader>e", telescope.explore_files, { desc = "explore files in the folder of the active buffer" })
nnoremap("<leader>s", telescope.live_grep, { desc = "search across current working directory" })
nnoremap("<leader>l", telescope_builtin.current_buffer_fuzzy_find, { desc = "search active buffer line" })
nnoremap("<leader>h", telescope_builtin.help_tags, { desc = "list help entries" })
nnoremap("<leader>k", telescope_builtin.keymaps, { desc = "list keymaps" })
nnoremap("<leader>$", telescope.snippets, { desc = "list snippets" })
-- telescope git
nnoremap("<leader>gc", telescope.git_commits, { desc = "list commits" })
nnoremap("<leader>gb", telescope.git_bcommits, { desc = "list commits that changed the actuve buffer" })
nnoremap("<leader>gw", telescope_extensions.git_worktree.git_worktrees, { desc = "list git worktrees" })
nnoremap("<leader>mp", ":MarkdownPreview<CR>", { desc = "start markdown preview" })
nnoremap("<leader>mc", ":MarkdownPreviewStop<CR>", { desc = "stop markdown preview" })
nnoremap(
  "<leader>gjm",
  ":GitConflictListQf<CR>:copen<CR>",
  { desc = "populate quickfix list with git conflicts (git jump merge) and open it" }
)
-- quickfix list navigation
nnoremap("[q", ":cprev<CR>", { desc = "quickfix list previous item" })
nnoremap("[Q", ":cfirst<CR>", { desc = "quickfix list first item" })
nnoremap("]q", ":cnext<CR>", { desc = "quickfix list next item" })
nnoremap("]Q", ":clast<CR>", { desc = "quickfix list last item" })
nnoremap("<leader>[", ":copen<CR>", { desc = "open quickfix list" })
nnoremap("<leader>]", ":cclose<CR>", { desc = "close quickfix list" })
-- location list navigation
-- The location list behaves just like the quickfix list except that it is local to the current window instead of being global to the Vim session.
-- So if you have five open windows, you can have up to five location lists, but only one quickfix list.
-- disable for know due it collides with paragraph navigation
-- nnoremap("{q", ":lprev<CR>", { desc = "" })
-- nnoremap("{Q", ":lfirst<CR>", { desc = "" })
-- nnoremap("}q", ":lnext<CR>", { desc = "" })
-- nnoremap("}Q", ":llast<CR>", { desc = "" })
-- nnoremap("<leader>{", ":lopen<CR>", { desc = "" })
-- nnoremap("<leader>}", ":lclose<CR>", { desc = "" })
-- move lines and selected blocks
nnoremap("<A-j>", ":m .+1<CR>==", { desc = "move current line down" })
nnoremap("<A-k>", ":m .-2<CR>==", { desc = "move current line up" })
inoremap("<A-j>", "<ESC>:m .+1<CR>==gi", { desc = "move current line down" })
inoremap("<A-k>", "<ESC>:m .-2<CR>==gi", { desc = "move current line up" })
vnoremap("<A-j>", ":m '>+1<CR>gv=gv", { desc = "move current line down" })
vnoremap("<A-k>", ":m '<-2<CR>gv=gv", { desc = "move current line up" })
