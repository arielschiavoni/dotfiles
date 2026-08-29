# Self-invalidating cache for atuin's init output.
#
# See starship.fish for the rationale. Same pattern: mtime-based invalidation
# against the binary, spawn-free hot path.
#
# NOTE: atuin init includes `set -gx ATUIN_SESSION (atuin uuid)` which spawns
# atuin at source time regardless of caching — this is inherent to atuin's
# design and is not avoidable without patching the init output.
if command -q atuin
    set -l cache ~/.cache/fish/atuin-init.fish
    set -l bin (type -p atuin)
    if not test -f $cache; or not test $cache -nt $bin
        mkdir -p ~/.cache/fish
        atuin init fish >$cache
    end
    source $cache
end
