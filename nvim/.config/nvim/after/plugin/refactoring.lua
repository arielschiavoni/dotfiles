local refactoring = require("refactoring")
local Remap = require("ariel.keymap")
local nnoremap = Remap.nnoremap
local vnoremap = Remap.vnoremap

local js_ts_print_var = 'console.log("%s %%s", JSON.stringify(%s, null, 2));'

-- https://github.com/ThePrimeagen/refactoring.nvim#configuration
refactoring.setup({
  printf_statements = {},
  print_var_statements = {
    typescript = {
      js_ts_print_var,
    },
    javascript = {
      js_ts_print_var,
    },
  },
})

vnoremap("<leader>rr", refactoring.select_refactor, { desc = "show refactor operations", silent = true, expr = false })

vnoremap(
  "<leader>re",
  [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Function')<CR>]],
  { desc = "Extract Function", silent = true, expr = false }
)

vnoremap(
  "<leader>rf",
  [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Function To File')<CR>]],
  { desc = "Extract Function To File", silent = true, expr = false }
)

vnoremap(
  "<leader>rv",
  [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Variable')<CR>]],
  { desc = "Extract Variable", silent = true, expr = false }
)

vnoremap(
  "<leader>ri",
  [[ <Esc><Cmd>lua require('refactoring').refactor('Inline Variable')<CR>]],
  { desc = "Inline Variable", silent = true, expr = false }
)

-- Extract block doesn't need visual mode
nnoremap(
  "<leader>rb",
  [[ <Cmd>lua require('refactoring').refactor('Extract Block')<CR>]],
  { desc = "Extract Block", silent = true, expr = false }
)

nnoremap(
  "<leader>rbf",
  [[ <Cmd>lua require('refactoring').refactor('Extract Block To File')<CR>]],
  { desc = "Extract Block To File", silent = true, expr = false }
)

-- Inline variable can also pick up the identifier currently under the cursor without visual mode
nnoremap(
  "<leader>ri",
  [[ <Cmd>lua require('refactoring').refactor('Inline Variable')<CR>]],
  { desc = "Inline Variable", silent = true, expr = false }
)

-- Remap in normal mode and passing { normal = true } will automatically find the variable under the cursor and print it
nnoremap(
  "<leader>rp",
  ":lua require('refactoring').debug.print_var({ normal = true })<CR>",
  { desc = "Find variable under the cursor and print it" }
)

-- Cleanup function: this remap should be made in normal mode
nnoremap(
  "<leader>rc",
  ":lua require('refactoring').debug.cleanup({})<CR>",
  { desc = "cleanup print statement added by refactoring plugin" }
)
