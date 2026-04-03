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
    local eslint_filetypes = {
      "javascript",
      "javascriptreact",
      "javascript.jsx",
      "typescript",
      "typescriptreact",
      "typescript.tsx",
      "vue",
      "svelte",
      "astro",
    }
    local eslint_config_files = {
      "eslint.config.js",
      "eslint.config.mjs",
      "eslint.config.cjs",
      "eslint.config.ts",
      "eslint.config.mts",
      "eslint.config.cts",
      ".eslintrc",
      ".eslintrc.js",
      ".eslintrc.cjs",
      ".eslintrc.mjs",
      ".eslintrc.json",
      ".eslintrc.yaml",
      ".eslintrc.yml",
    }
    local eslint = require("nvim-eslint")

    local function has_eslint_config(bufnr)
      return vim.fs.root(bufnr, eslint_config_files) ~= nil
    end

    -- https://github.com/esmuellert/nvim-eslint?tab=readme-ov-file#configuration
    eslint.user_config.settings = {
      workingDirectory = function(bufnr)
        return {
          -- This function sets the package.json folder of the current buffer as the working directory
          -- It adds support for monorepos
          directory = vim.fs.root(bufnr, { "package.json" }),
        }
      end,
    }

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("custom-eslint", { clear = true }),
      pattern = eslint_filetypes,
      callback = function(args)
        -- nvim-eslint autostarts by filetype, so gate it on a real ESLint config.
        if has_eslint_config(args.buf) then
          eslint.start_client_for_buffer(args.buf)
        end
      end,
    })

    -- Handle buffers that were already open before this plugin finished loading.
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.tbl_contains(eslint_filetypes, vim.bo[bufnr].filetype) then
        if has_eslint_config(bufnr) then
          eslint.start_client_for_buffer(bufnr)
        end
      end
    end
  end,
}
