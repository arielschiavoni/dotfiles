# Cache atuin init to avoid spawning external process (~23ms saved)
set -l cache_file ~/.cache/fish/atuin_init.fish
if not test -f $cache_file
    atuin init fish >$cache_file
end
source $cache_file
