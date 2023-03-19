return {
  "iamcco/markdown-preview.nvim",
  build = "cd app && npm install",
  ft = { "markdown" },
  config = function()
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
    vim.keymap.set("n", "<leader>mp", ":MarkdownPreview<CR>", { desc = "start markdown preview" })
    vim.keymap.set("n", "<leader>mc", ":MarkdownPreviewStop<CR>", { desc = "stop markdown preview" })
  end,
}
