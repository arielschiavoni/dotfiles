
switch (uname)
    case Darwin
        eval "$(/opt/homebrew/bin/brew shellenv)"
        set -gx PATH /opt/homebrew/opt/gnupg@2.2/bin $PATH
        set -gx PATH /opt/homebrew/opt/openssl@3/bin $PATH
    case Linux
    case '*'
end
set -gx LC_ALL en_US.UTF-8
set -gx LANG en_US.UTF-8
set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
set -gx MY_VIMRC ~/.config/nvim/init.lua
set -gx DOTFILES $HOME/personal/dotfiles
set -gx GOPATH $HOME/go
set -gx DENO_INSTALL $HOME/.deno
set -gx BUN_INSTALL $HOME/.bun
# if a new version is installed the following symlink needs to be created
# to replace apples defaut clan compiler
# sudo ln -s (which gcc-13) /usr/local/bin/gcc
set -gx CC /opt/homebrew/Cellar/gcc/13.2.0/bin/gcc-13


# add new directories to PATH
set -gx PATH $GOPATH/bin $PATH
set -gx PATH $HOME/.cargo/bin $PATH
set -gx PATH $DENO_INSTALL/bin $PATH
set -gx PATH $HOME/.local/bin $PATH
set -gx PATH $BUN_INSTALL/bin $PATH
set -gx PATH $HOME/.local/share/nvim/mason/bin $PATH
set -gx PATH /opt/homebrew/opt/python@3.11/libexec/bin $PATH
set -gx PATH /opt/homebrew/opt/git/share/git-core/contrib/git-jump $PATH
set -gx PATH /opt/homebrew/opt/gnu-sed/libexec/gnubin $PATH


# The DEFAULT_COMMAND (also used on vim) finds only files in the current directory, it includes
# hidden files and files ignored by git (dist, build, reports, etc)
# The list of hidden folders or files (node_modules, .git, etc) is controlled by .config/fd/ignore
set -gx FZF_DEFAULT_OPTS  ""
set -gx FZF_DEFAULT_COMMAND  "fd --type file --hidden --no-ignore-vcs"

# For changing directories I always start from the HOME (instead of the current directory)
# to allow directory changes from any place. Additionally I don't care about files in this case
# so I use the type directory to only show directory results.
set -gx FZF_ALT_C_COMMAND  "fd . $HOME --type directory --hidden --no-ignore-vcs -d 5 --ignore-file ~/.config/fish/.alt-c-fd-ignore"
set -gx FZF_ALT_C_OPTS  ""

# The CTRL_T_COMMAND is almost identical to the DEFAULT_COMMAND but it does not limit the results to
# files. It includes files and folders results. It is useful to apply operations on multiple files or
# dirs
set -gx FZF_CTRL_T_COMMAND  "fd --hidden --no-ignore-vcs"
set -gx FZF_CTRL_T_OPTS  "--preview 'bat --style=numbers --color=always --line-range :500 {}'"

set -gx MANPAGER "nvim +Man!"
set -gx LESS "-R"

# pnpm
set -gx PNPM_HOME $HOME/pnpm
set -gx PATH $PNPM_HOME $PATH

# opam
source $HOME/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

# fnm
fnm env --use-on-cd --log-level quiet | source

# starship prompt
starship init fish | source

# export secrets
source $HOME/.profile
