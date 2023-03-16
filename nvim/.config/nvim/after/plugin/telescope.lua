local telescope = require("telescope")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local actions_layout = require("telescope.actions.layout")
local themes = require("telescope.themes")

telescope.setup({
  defaults = {
    -- layout_strategy = "vertical",
    -- layout_config = {
    --   vertical = { width = 0.8 },
    --   -- other layout configuration here
    -- },
    file_sorter = sorters.get_fzy_sorter,
    prompt_prefix = "> ",
    color_devicons = true,

    file_previewer = previewers.vim_buffer_cat.new,
    grep_previewer = previewers.vim_buffer_vimgrep.new,
    qflist_previewer = previewers.vim_buffer_qflist.new,

    mappings = {
      i = {
        ["<esc>"] = actions.close,
        ["<C-q>"] = actions.send_to_qflist,
        ["<C-j>"] = actions.cycle_previewers_next,
        ["<C-k>"] = actions.cycle_previewers_prev,
        ["<M-p>"] = actions_layout.toggle_preview,
      },
      n = {
        ["<M-p>"] = actions_layout.toggle_preview,
      },
    },
  },
  -- pickers = {
  --   find_files = {
  --     theme = "dropdown",
  --   },
  -- },
  extensions = {
    fzy_native = {
      override_generic_sorter = false,
      override_file_sorter = true,
    },
    ["ui-select"] = {
      themes.get_dropdown(),
    },
  },
})

-- extensions
telescope.load_extension("fzy_native")
telescope.load_extension("file_browser")
telescope.load_extension("git_worktree")
telescope.load_extension("harpoon")
telescope.load_extension("ui-select")

-- keymaps
local Remap = require("ariel.keymap")
local nnoremap = Remap.nnoremap

local telescope_builtin = require("telescope.builtin")
local telescope_extensions = require("telescope").extensions
local telescope_custom = require("ariel.telescope")

nnoremap("<leader>t", ":Telescope<CR>", { desc = "open telescope overwiew" })
nnoremap("<leader>p", telescope_custom.project_files, { desc = "list git files respecting .gitignore" })
nnoremap("<leader>f", telescope_custom.find_files, { desc = "list files in the current working directory" })
nnoremap("<leader>.", telescope_custom.find_dotfiles, { desc = "list dotfiles" })
nnoremap("<leader>b", telescope_builtin.buffers, { desc = "list open buffers" })
nnoremap("<leader>e", telescope_custom.explore_files, { desc = "explore files in the folder of the active buffer" })
nnoremap("<leader>s", telescope_custom.live_grep, { desc = "search across current working directory" })
nnoremap("<leader>l", telescope_builtin.current_buffer_fuzzy_find, { desc = "search active buffer line" })
nnoremap("<leader>h", telescope_builtin.help_tags, { desc = "list help entries" })
nnoremap("<leader>k", telescope_builtin.keymaps, { desc = "list keymaps" })
nnoremap("<leader>gc", telescope_custom.git_commits, { desc = "list commits" })
nnoremap("<leader>gb", telescope_custom.git_bcommits, { desc = "list commits that changed the active buffer" })
nnoremap("<leader>gs", telescope_custom.git_scommits, { desc = "list commits containing the selected text" })
nnoremap("<leader>gw", telescope_extensions.git_worktree.git_worktrees, { desc = "list git worktrees" })
