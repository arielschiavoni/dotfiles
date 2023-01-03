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
nnoremap("<leader>w", ":w!<CR>", { desc = "save current buffer" })
nnoremap("<leader>W", ":wa!<CR>", { desc = "save all open buffers" })
nnoremap("<leader>n", ":enew<CR>", { desc = "create new buffer" })
nnoremap("<leader>??", ":edit scratchpad.ts<CR>", { desc = "open typescript scratchpad file" })
nnoremap("<leader>?r", function()
  require("sniprun").run()
end, { desc = "sniprun current line" })
vnoremap("<leader>?r", function()
  require("sniprun").run()
end, { desc = "sniprun visual selection" })
nnoremap("<leader>?c", function()
  require("sniprun.display").close_all()
end, { desc = "sniprun clear virtual text" })
nnoremap("<leader><leader>", ":bd<CR>", { desc = "close current buffer" })
nnoremap("<leader>|", ":vsplit<CR>", { desc = "create vertical split" })
nnoremap("<leader>-", ":split<CR>", { desc = "create horizontal split" })
nnoremap("<leader>~", ":let @* = expand('%:p')<CR>", { desc = "copy buffer's absolute path to clipboard" })
nnoremap("<leader>`", ":let @* = expand('%:t')<CR>", { desc = "copy buffer's file name to clipboard" })
nnoremap("<leader>d", ":put =strftime('%d/%m/%Y')<CR>", { desc = "insert current date" })
nnoremap("<up>", ":echoerr 'use h j k l 😃'<CR>", { desc = "disable arrow keys in normal mode" })
nnoremap("<down>", ":echoerr 'use h j k l 😃'<CR>", { desc = "disable arrow keys in normal mode" })
nnoremap("<left>", ":echoerr 'use h j k l 😃'<CR>", { desc = "disable arrow keys in normal mode" })
nnoremap("<right>", ":echoerr 'use h j k l 😃'<CR>", { desc = "disable arrow keys in normal mode" })
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
nnoremap("<leader>gb", telescope.git_bcommits, { desc = "list commits that changed the active buffer" })
nnoremap("<leader>gs", telescope.git_scommits, { desc = "list commits containing the selected text" })
nnoremap("<leader>gw", telescope_extensions.git_worktree.git_worktrees, { desc = "list git worktrees" })
nnoremap("<leader>mp", ":MarkdownPreview<CR>", { desc = "start markdown preview" })
nnoremap("<leader>mc", ":MarkdownPreviewStop<CR>", { desc = "stop markdown preview" })
nnoremap(
  "<leader>gjm",
  ":GitConflictListQf<CR>:copen<CR>",
  { desc = "populate quickfix list with git conflicts (git jump merge) and open it" }
)
-- harpoon
local harpoon_mark = require("harpoon.mark")
local harpoon_ui = require("harpoon.ui")

nnoremap("<leader>a", harpoon_mark.add_file, { desc = "add file to harpoon list", silent = true })
nnoremap("<leader>z", harpoon_ui.toggle_quick_menu, { desc = "toggle harpoon UI", silent = true })
nnoremap("<leader>hm", ":Telescope harpoon marks<CR>", { desc = "list harpoon marks", silent = true })

nnoremap("<leader>1", function()
  harpoon_ui.nav_file(1)
end, { desc = "navigate to 1st harpoon file", silent = true })
nnoremap("<leader>2", function()
  harpoon_ui.nav_file(2)
end, { desc = "navigate to 2nd harpoon file", silent = true })
nnoremap("<leader>3", function()
  harpoon_ui.nav_file(3)
end, { desc = "navigate to 3rd harpoon file", silent = true })
nnoremap("<leader>4", function()
  harpoon_ui.nav_file(4)
end, { desc = "navigate to 4th harpoon file", silent = true })

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

nnoremap("<C-u>", "<C-u>zz", { desc = "page up and center" })
nnoremap("<C-d>", "<C-d>zz", { desc = "page down and center" })
nnoremap("n", "nzz", { desc = "next and center" })
