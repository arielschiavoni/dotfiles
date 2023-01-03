vim.api.nvim_exec(
  [[
function OpenMarkdownPreview (url)
  execute "silent ! chrome --args --new-window " . a:url
endfunction
]],
  false
)
vim.g.mkdp_filetypes = { "markdown" }
vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
vim.g.mkdp_auto_close = 1

-- keymaps
local Remap = require("ariel.keymap")
local nnoremap = Remap.nnoremap

nnoremap("<leader>mp", ":MarkdownPreview<CR>", { desc = "start markdown preview" })
nnoremap("<leader>mc", ":MarkdownPreviewStop<CR>", { desc = "stop markdown preview" })
