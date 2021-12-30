set -l source_dir (dirname (status -f))

source $source_dir/iterm2_shell_integration.fish
source $source_dir/env.fish
source $source_dir/aliases.fish

fish_user_key_bindings
