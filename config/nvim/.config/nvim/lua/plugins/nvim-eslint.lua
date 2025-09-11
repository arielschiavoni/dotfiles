return {
  "esmuellert/nvim-eslint",
  ft = {
    "javascript",
    "javascriptreact",
    "javascript.jsx",
    "typescript",
    "typescriptreact",
    "typescript.tsx",
    "vue",
    "svelte",
    "astro",
  },
  config = function()
    -- https://github.com/esmuellert/nvim-eslint?tab=readme-ov-file#configuration
    require("nvim-eslint").setup({
      settings = {
        workingDirectory = function(bufnr)
          return {
            -- This function sets the package.json folder of the current buffer as the working directory
            -- It adds support for monorepos
            directory = vim.fs.root(bufnr, { "package.json" }),
          }
        end,
      },
    })
  end,
}
