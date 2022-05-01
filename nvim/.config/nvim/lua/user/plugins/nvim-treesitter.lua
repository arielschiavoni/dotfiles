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
    "html",
    "java",
    "javascript",
    "json",
    "json5",
    "lua",
    "make",
    "ocaml",
    "python",
    "rust",
    "toml",
    "typescript",
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
      init_selection = "gnn", -- maps in normal mode to init scope/node selection
      node_incremental = "grn", -- increments selection to upper named parent
      scope_incremental = "grc", -- increments selection to the upper scope (as defined in locals.scm)
      node_decremental = "grm", -- decrements selection to the previous node
    },
  },
  -- required by "Comment" and "nvim-ts-context-commentstring" plugins to properly comment jsx/tsx files
  context_commentstring = {
    enable = true,
    enable_autocmd = false,
  },
})

--vim.api.nvim_exec([[
--  set foldmethod=expr
--  set foldexpr=nvim_treesitter#foldexpr()
--]], true)
