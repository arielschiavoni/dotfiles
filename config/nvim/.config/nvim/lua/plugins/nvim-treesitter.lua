return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      -- Per-buffer treesitter setup, applied to every filetype.
      -- pcall is used so that filetypes without a parser (e.g. empty scratch
      -- buffers) silently skip rather than raising an error.
      --
      -- Folds: vim.wo[0][0] sets the option window-locally for the current
      -- window only (the [0][0] form avoids polluting other windows showing
      -- the same buffer).
      --
      -- Indentation: experimental per the nvim-treesitter README. smartindent
      -- (set globally in set.lua) is ignored by Neovim when indentexpr is set,
      -- so it continues to act as a fallback for filetypes without a parser.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "*" },
        callback = function()
          pcall(vim.treesitter.start)
          vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.wo[0][0].foldmethod = "expr"
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })

      -- Ensure parsers are installed. Idempotent (no-op if already installed)
      -- and runs asynchronously in the background.
      require("nvim-treesitter").install({
        "bash",
        "c",
        "cpp",
        "css",
        "dockerfile",
        "fish",
        "gitcommit",
        "go",
        "gomod",
        "gosum",
        "gotmpl",
        "gowork",
        "graphql",
        "hcl",
        "html",
        "http",
        "hurl",
        "java",
        "javascript",
        "json",
        "json5",
        "lua",
        "make",
        "markdown",
        "markdown_inline",
        "mermaid",
        "ocaml",
        "python",
        "regex",
        "rust",
        "terraform",
        "toml",
        "tsx",
        "typescript",
        "vim",
        "vimdoc",
        "xml",
        "yaml",
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
        },
        move = {
          set_jumps = true,
        },
      })

      local select = require("nvim-treesitter-textobjects.select")
      local move = require("nvim-treesitter-textobjects.move")
      local swap = require("nvim-treesitter-textobjects.swap")

      -- select
      vim.keymap.set({ "x", "o" }, "af", function()
        select.select_textobject("@function.outer", "textobjects")
      end, { desc = "Select outer function" })
      vim.keymap.set({ "x", "o" }, "if", function()
        select.select_textobject("@function.inner", "textobjects")
      end, { desc = "Select inner function" })
      vim.keymap.set({ "x", "o" }, "ac", function()
        select.select_textobject("@class.outer", "textobjects")
      end, { desc = "Select outer class" })
      vim.keymap.set({ "x", "o" }, "ic", function()
        select.select_textobject("@class.inner", "textobjects")
      end, { desc = "Select inner class" })

      -- move
      vim.keymap.set({ "n", "x", "o" }, "]f", function()
        move.goto_next_start("@function.outer", "textobjects")
      end, { desc = "Next function start" })
      vim.keymap.set({ "n", "x", "o" }, "[f", function()
        move.goto_previous_start("@function.outer", "textobjects")
      end, { desc = "Prev function start" })
      vim.keymap.set({ "n", "x", "o" }, "]F", function()
        move.goto_next_end("@function.outer", "textobjects")
      end, { desc = "Next function end" })
      vim.keymap.set({ "n", "x", "o" }, "[F", function()
        move.goto_previous_end("@function.outer", "textobjects")
      end, { desc = "Prev function end" })
      -- ]p/[p: parameter jumps (renamed from ]]/[[ to avoid conflict with Snacks.words.jump)
      vim.keymap.set({ "n", "x", "o" }, "]p", function()
        move.goto_next_start("@parameter.inner", "textobjects")
      end, { desc = "Next parameter" })
      vim.keymap.set({ "n", "x", "o" }, "[p", function()
        move.goto_previous_start("@parameter.inner", "textobjects")
      end, { desc = "Prev parameter" })

      -- swap
      vim.keymap.set("n", "<leader>>", function()
        swap.swap_next("@parameter.inner")
      end, { desc = "Swap next parameter" })
      vim.keymap.set("n", "<leader><", function()
        swap.swap_previous("@parameter.outer")
      end, { desc = "Swap prev parameter" })
    end,
  },
}
