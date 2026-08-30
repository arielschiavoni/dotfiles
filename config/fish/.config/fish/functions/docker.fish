function docker --wraps podman -d "Run podman in place of docker"
    # Previously `alias docker podman` in conf.d/abbr.fish. An alias is just a
    # function, so this is equivalent - but living in functions/ means it is
    # autoloaded and therefore also works in non-interactive shells. Defining it
    # in conf.d/50-abbr.fish would have put it behind that file's
    # `status is-interactive` guard, silently breaking `docker` for scripts and
    # tmux popups.
    podman $argv
end
