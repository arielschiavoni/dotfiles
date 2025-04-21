#!/bin/bash

sudo pacman -S --needed \
	ghostty \
	neovim \
	neofetch \
	tmux \
	fzf \
	ripgrep \
	fd \
	yazi \
	ffmpeg \
	jq \
	chafa \
	7zip \
	poppler \
	zoxide \
	imagemagick \
	starship \
	fish \
	rust \
	ocaml \
	bat \
	git \
	mise \
	bottom \
	eza \
	git-delta \
	gopass \
	shellcheck \
	stylua \
	hurl \
	hyperfine \
	luarocks \
	fx \
	ttf-jetbrains-mono-nerd \
	stow \
  atuin \
  terraform \
  wl-clipboard


# this packages are not available on the main repositories
# they are available in the Arch User Repo (AUR) and need to be installed with care a review!
yay -S --needed \
	google-chrome \
	sesh-bin \
  extension-manager \
  1password
