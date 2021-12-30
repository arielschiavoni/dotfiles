#!/bin/bash

xcode-select --install

DOTFILES=~/personal/dotfiles
WORK=~/work
mkdir -p $DOTFILES $WORK

git clone https://github.com/arielschiavoni/dotfiles.git $DOTFILES

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Make sure we’re using the latest Homebrew.
brew update

# install all packages defined in Brewfile
brew bundle --file Brewfile --force cleanup

# upgrade Brewfile witht the current status of packages installed on the system
# brew bundle dump --describe --force


# configure fish as the default shell
if [[ ! $(echo $SHELL) == $(which fish) ]]; then
  # fish to list of shells
  sudo sh -c "echo $(which fish) >> /etc/shells"

  # set fish as the default shell
  chsh -s $(which fish)
fi

# languages and package managers (node, go, ocaml, rust)
fnm install 14
fnm use 14
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh


# setup iterm2 to read config from the dotfiles directory

# specify the preferences directory
defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "$DOTFILES/iterm2"

# tell iterm2 to use the custom preferences in the directory
defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true
