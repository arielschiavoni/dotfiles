require("git-conflict").setup({
  default_mappings = true, -- disable buffer local mapping created by this plugin
  disable_diagnostics = false, -- This will disable the diagnostics in a buffer whilst it is conflicted
  highlights = { -- They must have background color, otherwise the default color will be used
    incoming = "DiffText",
    current = "DiffAdd",
  },
})

-- keymaps
local Remap = require("ariel.keymap")
local nnoremap = Remap.nnoremap

nnoremap(
  "<leader>gjm",
  ":GitConflictListQf<CR>:copen<CR>",
  { desc = "populate quickfix list with git conflicts (git jump merge) and open it" }
)
