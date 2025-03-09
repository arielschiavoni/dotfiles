return {
  "iamcco/markdown-preview.nvim",
  ft = { "markdown" },
  keys = {
    {
      "<leader>mp",
      ":MarkdownPreview<CR>",
      ft = "markdown",
      desc = "Markdown Preview",
    },
  },
  cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  build = "cd app && npm install",
  init = function()
    vim.g.mkdp_filetypes = { "markdown" }
    vim.cmd([[
      function OpenMarkdownPreview (url)
        execute "silent ! chrome --args --new-window " . a:url
      endfunction
       ]])
    -- a custom Vim function name to open preview page, this function will receive URL as param
    vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
    -- nvim will auto close current preview window when changing from Markdown buffer to another buffer
    vim.g.mkdp_auto_close = 1
  end,
}
