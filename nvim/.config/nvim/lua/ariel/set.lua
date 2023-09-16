-- set <leader> key to space (default is '\')
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.hidden = true -- Enable background buffers
vim.opt.ignorecase = true -- Ignore case
vim.opt.joinspaces = false -- No double spaces with join
vim.opt.list = true -- Show some invisible characters
vim.opt.number = true -- Show line numbers
vim.opt.relativenumber = true -- Relative line numbers
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
-- vim.opt.colorcolumn = "80"
vim.opt.guicursor = "n-i:blinkon100,i-ci-ve:ver25"
vim.opt.shortmess:append("c") -- Don't pass messages to |ins-completion-menu|.
-- Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
-- delays and poor user experience.
vim.opt.updatetime = 50
vim.opt.foldlevelstart = 99 -- don't fold regions of code please!
vim.opt.autoread = true -- reload file when it is externally changed
vim.opt.showtabline = 0 -- disable tab line
vim.opt.showmode = false

-- Cursorline highlighting control
--  Only have it on in the active buffer
vim.opt.cursorline = true -- Highlight the current line
local cursor_line_control_group = vim.api.nvim_create_augroup("CursorLineControl", { clear = true })
local set_cursorline = function(event, value, pattern)
  vim.api.nvim_create_autocmd(event, {
    group = cursor_line_control_group,
    pattern = pattern,
    callback = function()
      -- overwrite global cursorline setting for the current buffer
      vim.opt_local.cursorline = value
    end,
  })
end
set_cursorline("WinLeave", false)
set_cursorline("WinEnter", true)
set_cursorline("FileType", false, "TelescopePrompt")

-- Spell suggestion control
vim.opt.spelllang = { "en" }
vim.opt.spellsuggest = { "best", "9" }
vim.opt.spell = false
local spell_group = vim.api.nvim_create_augroup("SpellsuggestControl", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = spell_group,
  pattern = { "markdown", "plaintext" },
  callback = function()
    -- overwrite global spell setting for the current buffer
    vim.opt_local.spell = true
  end,
})

vim.opt.winbar = "%=%m %f"
vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"
