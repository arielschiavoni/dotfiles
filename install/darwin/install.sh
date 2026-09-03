#!/bin/bash

xcode-select --install

DOTFILES=~/code/personal/dotfiles
WORK=~/code/work
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
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# build and install the Rust command line tools into ~/.cargo/bin
#
# --force is required, not cosmetic: cargo records installs as
# "name version (source)" with no content hash, and every crate here inherits
# 0.1.0 from the workspace and never bumps it. Without --force, any crate whose
# source changed is silently skipped as "already installed".
for tool in "$DOTFILES"/tools/crates/*/; do
  cargo install --path "$tool" --locked --force
done

# devbox-open-url is built by the loop above; loading it as a launchd agent is
# left to devbox/scripts/create.sh so the agent has a single owner.

# install all yazi plugins
ya pkg install

# github extensions
gh extension install dlvhdr/gh-dash
gh extension install arielschiavoni/gh-list-repos
