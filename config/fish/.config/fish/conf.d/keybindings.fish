# https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_default_key_bindings.fish
fish_default_key_bindings
# https://fishshell.com/docs/current/interactive.html#vi-mode-commands
# https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_vi_key_bindings.fish
# fish_vi_key_bindings
bind ctrl-n 'nvim .'

# alt-r: full config reload (see the fish_reload function). Guarded on an empty
# command line so it can never discard something you were mid-way typing - the
# same idiom fish uses for its own alt-d binding.
bind alt-r 'if test -z "$(commandline)"; fish_reload; end'
