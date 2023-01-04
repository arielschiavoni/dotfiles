-- set <leader> key to space (default is '\')
vim.g.mapleader = " "
vim.g.netrw_banner = 0
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.hidden = true -- Enable background buffers
vim.opt.ignorecase = true -- Ignore case
vim.opt.joinspaces = false -- No double spaces with join
vim.opt.list = true -- Show some invisible characters
vim.opt.number = true -- Show line numbers
vim.opt.relativenumber = true -- Relative line numbers
vim.opt.cursorline = false -- Highlight current line
vim.opt.scrolloff = 8 -- Lines of context
vim.opt.shiftround = true -- Round indent
vim.opt.shiftwidth = 2 -- Size of an indent
vim.opt.sidescrolloff = 8 -- Columns of context
vim.opt.smartcase = true -- Do not ignore case with capitals
vim.opt.smartindent = true -- Insert indents automatically
vim.opt.splitbelow = true -- Put new windows below current
vim.opt.splitright = true -- Put new windows right of current
vim.opt.tabstop = 2 -- Number of spaces tabs count for
vim.opt.termguicolors = true -- True color support
vim.opt.wildmode = { "list", "longest" } -- Command-line completion mode
vim.opt.completeopt = { "menu", "menuone", "noselect" } -- Command-line completion mode
vim.opt.wrap = false -- Disable line wrap
vim.opt.scl = "yes" -- force the signcolumn to appear
vim.opt.swapfile = false -- disable swapfile
vim.opt.cmdheight = 1 -- Give more space for displaying messages.
vim.opt.colorcolumn = "80"
vim.opt.guicursor = "n-i:blinkon100,i-ci-ve:ver25"
vim.opt.shortmess:append("c") -- Don't pass messages to |ins-completion-menu|.
-- Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
-- delays and poor user experience.
vim.opt.updatetime = 50
vim.opt.timeoutlen = 500
