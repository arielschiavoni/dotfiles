# Self-invalidating cache for starship's init output.
#
# Generating it costs a subprocess spawn (~30ms on macOS: two Endpoint Security
# extensions hook every exec; ~2ms in the devbox). The cache is a plain file
# sourced directly — no spawns on the hot path.
#
# Invalidation: mtime comparison against the binary. A brew/mise upgrade writes
# a newer binary, so the next shell start regenerates the cache automatically.
# No manual rebuild step.
if command -q starship
    set -l cache ~/.cache/fish/starship-init.fish
    set -l bin (type -p starship)
    if not test -f $cache; or not test $cache -nt $bin
        mkdir -p ~/.cache/fish
        starship init fish --print-full-init >$cache
    end
    source $cache
end
