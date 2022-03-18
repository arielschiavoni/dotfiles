set -l source_dir (dirname (status -f))

source $source_dir/env.fish
source $source_dir/abbr.fish
source $source_dir/functions.fish

fish_user_key_bindings
theme_gruvbox dark
