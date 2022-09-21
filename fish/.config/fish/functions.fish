function ctrldot -d "Launch Neovim dotfiles finder from the shell"
  nvim -c 'lua require(\'user.plugins.telescope\').find_dotfiles()'
end


function find_password -d "Fuzzy searches a password in all gopass stores and copies it to the clipboard after selection"
  # disable preview of password :-)
  # gopass show --clip (gopass ls --flat | fzf)
  # redirect output to pbcopy because --clip only copies the first line!
  # gopass show --clip (gopass ls --flat | fzf --preview "gopass show {}")
  gopass show (gopass ls --flat | fzf --preview "gopass show {}") | pbcopy
end

function fish_user_key_bindings -d "Set custom key bindings"
  # https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_default_key_bindings.fish
  fish_default_key_bindings
  # https://fishshell.com/docs/current/interactive.html#vi-mode-commands
  # https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_vi_key_bindings.fish
  # fish_vi_key_bindings
  fzf_key_bindings

  bind \ck up-or-search
  bind \cj down-or-search

  bind \cg find_password # TODO: find out why the prompt wait for an CR to finish the command
  bind \cf tmux-sessionizer
  bind \cs tmux-find-session
end

function chrome -d "Google Chrome alias"
    open -na "Google Chrome" $argv
end
