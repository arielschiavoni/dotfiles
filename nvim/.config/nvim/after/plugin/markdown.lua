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
