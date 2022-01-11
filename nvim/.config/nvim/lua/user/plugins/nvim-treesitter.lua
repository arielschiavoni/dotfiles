
require('nvim-treesitter.configs').setup({
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
      init_selection = 'gnn', -- maps in normal mode to init scope/node selection
      node_incremental = 'grn', -- increments selection to upper named parent
      scope_incremental = 'grc', -- increments selection to the upper scope (as defined in locals.scm)
      node_decremental = 'grm', -- decrements selection to the previous node
    },
  },
  ensure_installed = 'maintained',
})

--vim.api.nvim_exec([[
--  set foldmethod=expr
--  set foldexpr=nvim_treesitter#foldexpr()
--]], true)

