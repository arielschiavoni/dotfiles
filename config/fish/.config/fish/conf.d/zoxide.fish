# Self-invalidating cache for zoxide's init output.
#
# See starship.fish for the rationale. Same pattern: mtime-based invalidation
# against the binary, spawn-free hot path.
if command -q zoxide
    set -l cache ~/.cache/fish/zoxide-init.fish
    set -l bin (type -p zoxide)
    if not test -f $cache; or not test $cache -nt $bin
        mkdir -p ~/.cache/fish
        zoxide init fish >$cache
    end
    source $cache
end
