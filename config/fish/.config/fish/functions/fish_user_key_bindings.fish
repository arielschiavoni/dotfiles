function fish_user_key_bindings -d "Custom key bindings, applied after fish installs its defaults"
    # fish calls this automatically during interactive setup, immediately after
    # installing the bindings named by $fish_key_bindings (here:
    # fish_default_key_bindings). Binding here rather than from conf.d means
    # these can never be clobbered by fish re-installing its defaults, and makes
    # the explicit `fish_default_key_bindings` call the old snippet needed
    # redundant.
    #
    # https://fishshell.com/docs/current/interactive.html#key-bindings

    bind ctrl-n 'nvim .'

    # alt-r: full config reload (see fish_reload). Guarded on an empty command
    # line so it can never discard something you were part-way through typing -
    # the same idiom fish uses for its own alt-d binding.
    bind alt-r 'if test -z "$(commandline)"; fish_reload; end'
end
