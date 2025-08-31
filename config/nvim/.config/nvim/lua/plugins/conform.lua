return {
  -- formatting
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  config = function()
    local prettier_filetypes = {
      "css",
      "graphql",
      "html",
      "javascript",
      "javascriptreact",
      "json",
      "jsonc",
      "markdown",
      "typescript",
      "typescriptreact",
      "yaml",
    }

    local formatters_by_ft = {
      lua = { "stylua" },
      ocaml = { "ocamlformat" },
      go = { "gofmt" },
      fish = { "fish_indent" },
      python = {
        -- To fix auto-fixable lint errors.
        "ruff_fix",
        -- To run the Ruff formatter.
        "ruff_format",
        -- To organize the imports.
        "ruff_organize_imports",
      },
      ["*"] = { "trim_whitespace" },
    }

    for _, prettier_filetype in ipairs(prettier_filetypes) do
      formatters_by_ft[prettier_filetype] = { "prettier" }
    end

    require("conform").setup({
      -- If this is set, Conform will run the formatter on save.
      -- It will pass the table to conform.format().
      format_on_save = function(bufnr)
        -- Disable with a global or buffer-local variable
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
          return
        end
        -- Disable autoformat for files in a certain path
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname:match("/node_modules/") then
          return
        end

        return { timeout_ms = 2000, lsp_format = "fallback" }
      end,
      formatters_by_ft = formatters_by_ft,
      -- Set the log level. Use `:ConformInfo` to see the location of the log file.
      log_level = vim.log.levels.OFF,
      -- Conform will notify you when a formatter errors
      notify_on_error = true,
    })

    vim.api.nvim_create_user_command("FormatDisable", function(args)
      if args.bang then
        -- FormatDisable! will disable formatting just for this buffer
        vim.b.disable_autoformat = true
      else
        vim.g.disable_autoformat = true
      end
    end, {
      desc = "Disable autoformat-on-save",
      bang = true,
    })

    vim.api.nvim_create_user_command("FormatEnable", function()
      vim.b.disable_autoformat = false
      vim.g.disable_autoformat = false
    end, {
      desc = "Re-enable autoformat-on-save",
    })

    vim.keymap.set(
      "n",
      "<leader>fd%",
      ":FormatDisable!<CR>",
      { desc = "disable auto format on save for the current buffer" }
    )
    vim.keymap.set("n", "<leader>fda", ":FormatDisable<CR>", { desc = "disable auto format on save" })
    vim.keymap.set("n", "<leader>fe", ":FormatEnable<CR>", { desc = "enable auto format on save" })
  end,
}
