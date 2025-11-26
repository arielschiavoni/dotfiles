# Cache zoxide init to avoid spawning external process (~5ms saved)
set -l cache_file ~/.cache/fish/zoxide_init.fish
if not test -f $cache_file
    zoxide init fish >$cache_file
end
source $cache_file
