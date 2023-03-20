set -l source_dir (dirname (status -f))
# remove default fish greeting
set -U fish_greeting


source $source_dir/env.fish
source $source_dir/abbr.fish
source $source_dir/functions.fish
source $source_dir/themes/tokyonight_moon.fish

fish_user_key_bindings
