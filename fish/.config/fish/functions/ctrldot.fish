function ctrldot -d "Launch Neovim dotfiles finder from the shell"
  nvim -c 'lua require(\'user.plugins.telescope\').find_dotfiles()'
end
