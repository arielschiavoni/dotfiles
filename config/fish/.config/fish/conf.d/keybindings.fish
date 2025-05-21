# https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_default_key_bindings.fish
fish_default_key_bindings
# https://fishshell.com/docs/current/interactive.html#vi-mode-commands
# https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_vi_key_bindings.fish
# fish_vi_key_bindings
bind \cg find_password # TODO: find out why the prompt wait for an CR to finish the command
bind \cn 'nvim .'
bind \cv 'env | fzf'
bind \cd 'gh dash'
