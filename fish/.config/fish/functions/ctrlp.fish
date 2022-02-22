function ctrlp -d "Launch Neovim file finder from the shell"
  nvim -c 'lua require(\'user.plugins.telescope\').find_files()'
end
