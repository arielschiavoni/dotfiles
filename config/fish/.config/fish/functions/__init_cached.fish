function __init_cached -d "Source a tool's shell-init output, cached and self-invalidating"
    # Generating a tool's init costs a subprocess spawn - roughly 3ms (starship),
    # 6ms (zoxide) and 17ms (atuin) on macOS, where two Endpoint Security
    # extensions hook every exec. The cache is a plain file sourced directly, so
    # the hot path spawns nothing.
    #
    # Invalidation is an mtime comparison against the tool binary: a brew or mise
    # upgrade writes a newer binary, so the next shell start regenerates the
    # cache. There is no manual rebuild step.
    #
    # Usage: __init_cached starship init fish --print-full-init

    set -l tool $argv[1]
    set -l args $argv[2..-1]

    command -q $tool; or return 0

    set -l cache $HOME/.cache/fish/$tool-init.fish
    set -l bin (command -v $tool)

    if not test -f $cache; or not test $cache -nt $bin
        mkdir -p $HOME/.cache/fish
        # Generate to a temp file and move into place, so a failed or partial
        # generation never leaves a corrupt cache to be sourced forever.
        set -l tmp $cache.tmp.$fish_pid
        if $tool $args >$tmp 2>/dev/null
            mv -f $tmp $cache
        else
            rm -f $tmp
            return 1
        end
    end

    source $cache
end
