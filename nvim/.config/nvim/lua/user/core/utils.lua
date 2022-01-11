local utils = {}

function utils.remap(mode, lhs, rhs, opts)
    local options = {noremap = true}
    if opts then options = vim.tbl_extend('force', options, opts) end
    vim.api.nvim_set_keymap(mode, lhs, rhs, options)
end

function utils.reload_config()
    for name,_ in pairs(package.loaded) do
      if name:match('^user') then
        package.loaded[name] = nil
      end
    end

    dofile(vim.env.MY_VIMRC)

    --print(vim.env.MY_VIMRC .. ' was reloaded')
end

return utils
