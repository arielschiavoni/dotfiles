# remove default fish greeting
set -U fish_greeting

set -gx LC_ALL en_US.UTF-8
set -gx LANG en_US.UTF-8
set -gx XDG_CONFIG_HOME $HOME/.config
set -gx EZA_CONFIG_DIR $HOME/.config/eza
set -gx WIREIT_LOGGER metrics
set -gx HUSKY 0
set -gx AWS_PROFILE renderman-dev
set -gx AWS_REGION eu-central-1

# add new directories to PATH
set -gx PATH $HOME/.cargo/bin $PATH

# export secrets
source $HOME/.profile
