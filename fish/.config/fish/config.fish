set -l source_dir (dirname (status -f))
# remove default fish greeting
set -U fish_greeting

source $source_dir/env.fish
source $source_dir/abbr.fish
source $source_dir/functions.fish

fish_user_key_bindings
fish_config theme choose "TokyoNight Moon"

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
