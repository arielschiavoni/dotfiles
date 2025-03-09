# remove default fish greeting
set -U fish_greeting

set -gx LC_ALL en_US.UTF-8
set -gx LANG en_US.UTF-8
set -gx GOPATH $HOME/go
set -gx DENO_INSTALL $HOME/.deno
set -gx BUN_INSTALL $HOME/.bun

# add new directories to PATH
set -gx PATH $GOPATH/bin $PATH
set -gx PATH $HOME/.cargo/bin $PATH
set -gx PATH $DENO_INSTALL/bin $PATH
set -gx PATH $HOME/.local/bin $PATH
set -gx PATH $BUN_INSTALL/bin $PATH

# export secrets
source $HOME/.profile
