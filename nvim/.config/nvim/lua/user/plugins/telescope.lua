local telescope = require('telescope')
local sorters = require('telescope.sorters')
local previewers = require('telescope.previewers')
local actions = require('telescope.actions')
local builtin = require('telescope.builtin')

telescope.setup({
  defaults = {
    file_sorter = sorters.get_fzy_sorter,
    prompt_prefix = ' >',
    color_devicons = true,

    file_previewer = previewers.vim_buffer_cat.new,
    grep_previewer = previewers.vim_buffer_vimgrep.new,
    qflist_previewer = previewers.vim_buffer_qflist.new,

    mappings = {
      i = {
        ['<C-x>'] = false,
        ['<C-q>'] = actions.send_to_qflist,
      },
    },
  },
  extensions = {
    fzy_native = {
      override_generic_sorter = false,
      override_file_sorter = true,
    },
  },
})

-- This will load fzy_native and have it override the default file sorter
telescope.load_extension('fzy_native')
telescope.load_extension('file_browser')

-- extends telescope with more funtions exported from this module (ariel.telescope)
local M = {}

M.find_dotfiles = function()
  builtin.git_files({
    prompt_title = '< dotfiles >',
    cwd = vim.env.DOTFILES,
  })
end

M.find_files = function()
  builtin.find_files({
    find_command = { 'fd', '--type', 'file', '--hidden', '--no-ignore-vcs' },
  })
end

M.live_grep = function()
  builtin.live_grep({
    vimgrep_arguments = { 'rg', '--color=never', '--no-heading', '--with-filename', '--line-number', '--column', '--smart-case', '--hidden', '-g', '!node_modules/**', '-g', '!.git/**' },
  })
end

return M
