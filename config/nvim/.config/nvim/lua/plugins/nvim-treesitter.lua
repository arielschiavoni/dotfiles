return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter-textobjects",
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
        "gitcommit",
        "go",
        "gomod",
        "gosum",
        "gotmpl",
        "gowork",
        "graphql",
        "hcl",
        "help",
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
        "norg",
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
        -- disable due it causes issues with hurl files
        enable = false,
        keymaps = {
          init_selection = ".", -- maps in normal mode to init scope/node selection
          node_incremental = ".", -- increments selection to upper named parent
          scope_incremental = ",", -- increments selection to the upper scope (as defined in locals.scm)
          node_decremental = ",", -- decrements selection to the previous node
        },
      },
      -- https://github.com/nvim-treesitter/nvim-treesitter-textobjects
      textobjects = {
        select = {
          enable = true,
          -- Automatically jump forward to textobj, similar to targets.vim
          lookahead = true,
          keymaps = {
            -- You can use the capture groups defined in textobjects.scm
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
            ["ac"] = "@class.outer",
            ["ic"] = "@class.inner",
          },
        },
        move = {
          enable = true,
          set_jumps = true, -- whether to set jumps in the jumplist
          goto_next_start = {
            ["]f"] = "@function.outer",
            ["]]"] = "@parameter.inner",
          },
          goto_next_end = {
            ["]F"] = "@function.outer",
          },
          goto_previous_start = {
            ["[f"] = "@function.outer",
            ["[["] = "@parameter.inner",
          },
          goto_previous_end = {
            ["[F"] = "@function.outer",
          },
        },
        swap = {
          enable = true,
          swap_next = { ["<leader>>"] = "@parameter.inner" },
          swap_previous = { ["<leader><"] = "@parameter.outer" },
        },
        lsp_interop = {
          enable = true,
          peek_definition_code = {
            ["gD"] = "@function.outer",
          },
        },
      },
    })
  end,
}
