function ctrldot -d "Launch Neovim dotfiles finder from the shell"
  nvim -c 'lua require(\'my.plugins.telescope\').find_dotfiles()'
end
