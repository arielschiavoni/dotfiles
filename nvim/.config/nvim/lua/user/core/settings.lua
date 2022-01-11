vim.opt.expandtab = true                                  -- Use spaces instead of tabs
vim.opt.hidden = true                                     -- Enable background buffers
vim.opt.ignorecase = true                                 -- Ignore case
vim.opt.joinspaces = false                                -- No double spaces with join
vim.opt.list = true                                       -- Show some invisible characters
vim.opt.number = true                                     -- Show line numbers
vim.opt.relativenumber = true                             -- Relative line numbers
vim.opt.cursorline = true                                 -- Highlight current line
vim.opt.scrolloff = 8                                     -- Lines of context
vim.opt.shiftround = true                                 -- Round indent
vim.opt.shiftwidth = 2                                    -- Size of an indent
vim.opt.sidescrolloff = 8                                 -- Columns of context
vim.opt.smartcase = true                                  -- Do not ignore case with capitals
vim.opt.smartindent = true                                -- Insert indents automatically
vim.opt.splitbelow = true                                 -- Put new windows below current
vim.opt.splitright = true                                 -- Put new windows right of current
vim.opt.tabstop = 2                                       -- Number of spaces tabs count for
vim.opt.termguicolors = true                              -- True color support
vim.opt.wildmode = {'list', 'longest'}                    -- Command-line completion mode
vim.opt.completeopt = {'menu', 'menuone', 'noselect'}     -- Command-line completion mode
vim.opt.wrap = false                                      -- Disable line wrap
vim.opt.background = 'dark'                               -- or 'light' for light mode

-- colorscheme
vim.cmd([[colorscheme gruvbox]])


-- commands and autocommands
vim.cmd("command! ReloadConfig lua require('core.utils').reload_config()")

vim.api.nvim_exec(
[[
augroup filetype_lua " Source nvim configuration upon lua files save
    autocmd!
    autocmd BufWritePost *.lua :ReloadConfig
augroup END
]],
true)

