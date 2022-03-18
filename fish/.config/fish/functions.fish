
function ctrldot -d "Launch Neovim dotfiles finder from the shell"
  nvim -c 'lua require(\'user.plugins.telescope\').find_dotfiles()'
end

function ctrlp -d "Launch Neovim file finder from the shell"
  nvim -c 'lua require(\'user.plugins.telescope\').find_files()'
end

function fish_user_key_bindings -d "Set custom key bindings"
  fzf_key_bindings
  bind \cp ctrlp
  bind \cj fzf-cd-widget # j for jump
end

function worktree -d "Creates a git worktree in the current working directory and sets its origin"
  set path $argv[1]
  set branch $argv[1]
  set origin origin

  git worktree add $path $branch
  git branch --set-upstream-to=$origin/$branch $branch
end

