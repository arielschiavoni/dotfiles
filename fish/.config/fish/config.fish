set -l source_dir (dirname (status -f))

source $source_dir/env.fish
source $source_dir/abbr.fish

fish_user_key_bindings
