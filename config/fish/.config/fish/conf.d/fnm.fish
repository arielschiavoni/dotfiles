# Cache fnm env to avoid spawning external process (~10ms saved)
set -l cache_file ~/.cache/fish/fnm_env.fish
if not test -f $cache_file
    fnm env --use-on-cd --shell fish >$cache_file
end
source $cache_file
