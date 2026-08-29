#!/bin/bash
# devbox user bootstrap - runs as the guest user on EVERY boot.
# Idempotent: each step checks its own state before acting.
set -euo pipefail

log() { echo "[devbox/user] $*"; }

# ---------------------------------------------------------------------------
# ~/share - Lima mounts the host ~/share here via virtiofs.
# Do NOT use for development work - virtiofs crosses the host VFS boundary and
# reintroduces host-OS per-syscall overhead.
# ---------------------------------------------------------------------------
mkdir -p "$HOME/share"

# ---------------------------------------------------------------------------
# ~/repos - clone dotfiles on first boot
# ---------------------------------------------------------------------------
DOTFILES_DIR="$HOME/repos/arielschiavoni/dotfiles"
DOTFILES_REPO="https://github.com/arielschiavoni/dotfiles.git"

mkdir -p "$HOME/repos/arielschiavoni"

if [ ! -d "$DOTFILES_DIR/.git" ]; then
  log "cloning dotfiles to $DOTFILES_DIR"
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  log "dotfiles already cloned"
fi

# ---------------------------------------------------------------------------
# stow - symlink devbox config packages into $HOME
# ---------------------------------------------------------------------------
log "stowing config packages into $HOME"
STOW_PACKAGES="agents bat btop claude eza fish gh-dash git hunk jj lazygit npm nvim opencode pi sesh starship tmux yazi"
(cd "$DOTFILES_DIR/config" && stow --target="$HOME" --restow $STOW_PACKAGES)

# ---------------------------------------------------------------------------
# mise config - symlink from dotfiles repo
# ---------------------------------------------------------------------------
MISE_CONFIG_DIR="$HOME/.config/mise"
MISE_CONFIG="$MISE_CONFIG_DIR/config.toml"
SOURCE_CONFIG="$DOTFILES_DIR/devbox/provision/mise.toml"

mkdir -p "$MISE_CONFIG_DIR"

if [ ! -L "$MISE_CONFIG" ] || [ "$(readlink "$MISE_CONFIG")" != "$SOURCE_CONFIG" ]; then
  log "linking mise config: $MISE_CONFIG -> $SOURCE_CONFIG"
  ln -sf "$SOURCE_CONFIG" "$MISE_CONFIG"
else
  log "mise config already linked"
fi

# ---------------------------------------------------------------------------
# mise install
# ---------------------------------------------------------------------------
log "running mise install (skips already-installed tools)"
# PARAM_GithubToken is injected at create time via --param in create.sh.
# It survives the sudo -i invocation because Lima passes PARAM_* via
# --preserve-env. Hard-fail if missing to catch misconfigured creates early.
GITHUB_TOKEN="${PARAM_GithubToken:?GithubToken param not set - re-create with GITHUB_TOKEN exported}"
export GITHUB_TOKEN
mise install

# ---------------------------------------------------------------------------
# fish shell - register as login shell and set as default
# ---------------------------------------------------------------------------
FISH_PATH="$(mise where "aqua:fish-shell/fish-shell")/fish"

if [ -x "$FISH_PATH" ]; then
  if ! grep -qxF "$FISH_PATH" /etc/shells; then
    log "registering fish in /etc/shells: $FISH_PATH"
    echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
  else
    log "fish already registered in /etc/shells"
  fi

  CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
  if [ "$CURRENT_SHELL" != "$FISH_PATH" ]; then
    log "setting fish as default shell for $USER"
    sudo chsh -s "$FISH_PATH" "$USER"
  else
    log "fish already set as default shell"
  fi
else
  log "WARN: fish binary not found at $FISH_PATH - skipping shell registration"
fi

log "user provisioning complete"
