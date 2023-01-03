local harpoon = require("harpoon")
local harpoon_mark = require("harpoon.mark")
local harpoon_ui = require("harpoon.ui")

harpoon.setup({
  global_settings = {
    -- sets the marks upon calling `toggle` on the ui, instead of require `:w`.
    save_on_toggle = false,

    -- saves the harpoon file upon every change. disabling is unrecommended.
    save_on_change = true,

    -- sets harpoon to run the command immediately as it's passed to the terminal when calling `sendCommand`.
    enter_on_sendcmd = false,

    -- closes any tmux windows harpoon that harpoon creates when you close Neovim.
    tmux_autoclose_windows = false,

    -- filetypes that you want to prevent from adding to the harpoon list menu.
    excluded_filetypes = { "harpoon" },

    -- set marks specific to each git branch inside git repository
    mark_branch = false,
  },
})

-- keymaps
local Remap = require("ariel.keymap")
local nnoremap = Remap.nnoremap

nnoremap("<leader>a", harpoon_mark.add_file, { desc = "add file to harpoon list", silent = true })
nnoremap("<leader>z", harpoon_ui.toggle_quick_menu, { desc = "toggle harpoon UI", silent = true })
nnoremap("<leader>hm", ":Telescope harpoon marks<CR>", { desc = "list harpoon marks", silent = true })

nnoremap("<leader>1", function()
  harpoon_ui.nav_file(1)
end, { desc = "navigate to 1st harpoon file", silent = true })
nnoremap("<leader>2", function()
  harpoon_ui.nav_file(2)
end, { desc = "navigate to 2nd harpoon file", silent = true })
nnoremap("<leader>3", function()
  harpoon_ui.nav_file(3)
end, { desc = "navigate to 3rd harpoon file", silent = true })
nnoremap("<leader>4", function()
  harpoon_ui.nav_file(4)
end, { desc = "navigate to 4th harpoon file", silent = true })
nnoremap("<leader>5", function()
  harpoon_ui.nav_file(5)
end, { desc = "navigate to 5th harpoon file", silent = true })
nnoremap("<leader>6", function()
  harpoon_ui.nav_file(6)
end, { desc = "navigate to 6th harpoon file", silent = true })
