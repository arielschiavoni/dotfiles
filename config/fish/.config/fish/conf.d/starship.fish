# Cache starship init to avoid spawning external process (~53ms saved)
set -l cache_file ~/.cache/fish/starship_init.fish
if not test -f $cache_file
    starship init fish --print-full-init >$cache_file
end
source $cache_file
