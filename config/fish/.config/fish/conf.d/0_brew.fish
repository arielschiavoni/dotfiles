# Cache uname result to avoid repeated calls
if not set -q __fish_uname_cached
    set -g __fish_uname_cached (uname)
end

if test $__fish_uname_cached = Darwin
    # This file name starts with 0_brew to force fish to load it first as most of the other
    # tools configured in conf.d depend on the binaries being available.
    # brew shellenv is terrible slow! ~500ms, so instead of running it on every shell start its results is
    # added here as a sort of "cache"
    # eval "$(/opt/homebrew/bin/brew shellenv)"
    # start
    set --global --export HOMEBREW_PREFIX /opt/homebrew

    set --global --export HOMEBREW_CELLAR /opt/homebrew/Cellar

    set --global --export HOMEBREW_REPOSITORY /opt/homebrew

    fish_add_path --global --move --path /opt/homebrew/bin /opt/homebrew/sbin

    if test -n "$MANPATH[1]"
        set --global --export MANPATH '' $MANPATH
    end

    if not contains /opt/homebrew/share/info $INFOPATH
        set --global --export INFOPATH /opt/homebrew/share/info $INFOPATH
    end

    # end

    set -gx PATH /opt/homebrew/opt/gnupg@2.2/bin $PATH
    set -gx PATH /opt/homebrew/opt/openssl@3/bin $PATH
    set -gx PATH /opt/homebrew/opt/python@3.11/libexec/bin $PATH
    set -gx PATH /opt/homebrew/opt/gnu-sed/libexec/gnubin $PATH
    set -gx PATH /opt/homebrew/opt/coreutils/libexec/gnubin $PATH
    set -gx PATH /opt/homebrew/opt/ncurses/bin $PATH
    # if a new version is installed the following symlink needs to be created
    # to replace apples defaut clan compiler
    # sudo ln -s (which gcc-15) $HOME/.local/bin/gcc
    set -gx CC /opt/homebrew/bin/gcc-15
end
