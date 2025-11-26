# Cache mise activate to avoid spawning external process (~44ms saved)
set -l cache_file ~/.cache/fish/mise_activate.fish
if not test -f $cache_file
    mise activate fish >$cache_file
end
source $cache_file
