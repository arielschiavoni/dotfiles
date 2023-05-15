return {
  { "nvim-treesitter/playground", cmd = "TSPlaygroundToggle" },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "JoosepAlviste/nvim-ts-context-commentstring",
      "nvim-treesitter/nvim-treesitter-context",
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        -- A list of parser names, or "all"
        ensure_installed = {
          "bash",
          "c",
          "cpp",
          "css",
          "dockerfile",
          "fish",
          "go",
          "graphql",
          "hcl",
          "help",
          "html",
          "http",
          "java",
          "javascript",
          "json",
          "json5",
          "lua",
          "make",
          "markdown",
          "markdown_inline",
          "mermaid",
          "norg",
          "ocaml",
          "python",
          "rust",
          "terraform",
          "toml",
          "typescript",
          "tsx",
          "vim",
          "yaml",
        },
        -- Install languages synchronously (only applied to `ensure_installed`)
        sync_install = false,
        highlight = {
          enable = true,
        },
        indent = {
          enable = true,
        },
        incremental_selection = {
          enable = true,
          -- mappings for incremental selection (only available on visual mode)
          keymaps = {
            init_selection = "<C-Up>", -- maps in normal mode to init scope/node selection
            node_incremental = "<C-Up>", -- increments selection to upper named parent
            scope_incremental = "<C-Up>", -- increments selection to the upper scope (as defined in locals.scm)
            node_decremental = "<C-Down>", -- decrements selection to the previous node
          },
        },
        -- required by "mini.comment" and "nvim-ts-context-commentstring" plugins to properly comment jsx/tsx files
        context_commentstring = {
          enable = true,
          enable_autocmd = false,
        },
      })

      require("treesitter-context").setup()
    end,
  },
}
