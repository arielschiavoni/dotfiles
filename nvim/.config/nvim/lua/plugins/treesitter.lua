return {
  { "nvim-treesitter/playground", cmd = "TSPlaygroundToggle" },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
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
          "java",
          "javascript",
          "json",
          "json5",
          "lua",
          "make",
          "norg",
          "ocaml",
          "python",
          "rust",
          "toml",
          "typescript",
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
      })

      local ft_to_parser = require("nvim-treesitter.parsers").filetype_to_parsername
      ft_to_parser.tf = "hcl" -- the tf (terraform) filetype will use the hcl parser and queries.
    end,
  },
}
