set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
fish_add_path --prepend --global $HOME/.local/share/nvim/mason/bin
set -gx MANPAGER "nvim +Man!"
set -gx LESS "-R"
