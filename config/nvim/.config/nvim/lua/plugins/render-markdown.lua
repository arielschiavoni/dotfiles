return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
  ft = { "markdown", "codecompanion" },
  config = function()
    require("render-markdown").setup({
      file_types = { "markdown", "vimwiki", "codecompanion" },
      completions = {
        lsp = { enabled = true },
        blink = { enabled = true },
      },
    })

    vim.keymap.set("n", "<leader>mp", ":RenderMarkdown buf_toggle<CR>", { desc = "Toggle markdown preview" })
  end,
}
