
switch (uname)
    case Darwin
        eval "$(/opt/homebrew/bin/brew shellenv)"
        set -gx JAVA_HOME (/usr/libexec/java_home -v11)
        set -gx PATH /opt/homebrew/opt/gnupg@2.2/bin $PATH
    case Linux
    case '*'
end
set -gx SHELL /opt/homebrew/bin/fish
set -gx LC_ALL en_US.UTF-8
set -gx LANG en_US.UTF-8
set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
set -gx MY_VIMRC ~/.config/nvim/init.lua
set -gx DOTFILES $HOME/personal/dotfiles
set -gx GOPATH $HOME/go
set -gx DENO_INSTALL $HOME/.deno
set -gx PYENV_ROOT $HOME/.pyenv

# add new directories to PATH
set -gx PATH $GOPATH/bin $PATH
set -gx PATH $HOME/.cargo/bin $PATH
set -gx PATH $HOME/.iterm2   $PATH
set -gx PATH $DENO_INSTALL/bin $PATH
set -gx PATH $HOME/.local/bin $PATH
set -gx PATH $PYENV_ROOT/bin $PATH


# The DEFAULT_COMMAND (also used on vim) finds only files in the current directory, it includes
# hidden files and files ignored by git (dist, build, reports, etc)
# The list of hidden folders or files (node_modules, .git, etc) is controlled by .config/fd/ignore
set -gx FZF_DEFAULT_OPTS  ""
set -gx FZF_DEFAULT_COMMAND  "fd --type file --hidden --no-ignore-vcs"

# For changing directories I always start from the HOME (instead of the current directory)
# to allow directory changes from any place. Additionally I don't care about files in this case
# so I use the type directory to only show directory results.
set -gx FZF_ALT_C_COMMAND  "fd . $HOME --type directory --hidden --no-ignore-vcs"
set -gx FZF_ALT_C_OPTS  ""

# The CTRL_T_COMMAND is almost identical to the DEFAULT_COMMAND but it does not limit the results to
# files. It includes files and folders results. It is useful to apply operations on multiple files or
# dirs
set -gx FZF_CTRL_T_COMMAND  "fd --hidden --no-ignore-vcs"
set -gx FZF_CTRL_T_OPTS  "--preview 'bat --style=numbers --color=always --line-range :500 {}'"

# opam
source $HOME/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

# fnm
fnm env --use-on-cd | source


#pyenv

status is-login; and pyenv init --path | source
status is-interactive; and pyenv init - | source

# aws
# aws profile audi-dev

# load other env variables (secrets)
source ~/.profile
