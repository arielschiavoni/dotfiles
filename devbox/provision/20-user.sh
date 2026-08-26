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
# stow - symlink all config packages into $HOME
# ---------------------------------------------------------------------------
log "stowing config packages into $HOME"
stow --dir="$DOTFILES_DIR/config" --target="$HOME" --restow */

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
# GITHUB_TOKEN raises the GitHub API rate limit from 60 to 5000 req/hour.
# Required when installing many tools in one shot. Set it in ~/.config/mise/config.toml
# or export it before running this script. An unscoped PAT is sufficient.
if [ -z "${GITHUB_TOKEN:-}" ]; then
  log "WARN: GITHUB_TOKEN is not set - GitHub API rate limit is 60 req/hour and may cause failures"
fi
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

# ---------------------------------------------------------------------------
# mise shell activation
# ---------------------------------------------------------------------------

# bash fallback
BASH_PROFILE="$HOME/.bash_profile"
if ! grep -q 'mise activate' "$BASH_PROFILE" 2>/dev/null; then
  log "adding mise activation to $BASH_PROFILE"
  cat >> "$BASH_PROFILE" << 'EOF'

# mise
eval "$(mise activate bash)"
EOF
fi

# fish
FISH_CONFIG_DIR="$HOME/.config/fish"
FISH_CONFIG="$FISH_CONFIG_DIR/config.fish"
mkdir -p "$FISH_CONFIG_DIR"
if ! grep -q 'mise activate' "$FISH_CONFIG" 2>/dev/null; then
  log "adding mise activation to $FISH_CONFIG"
  cat >> "$FISH_CONFIG" << 'EOF'

# mise
mise activate fish | source
EOF
fi

log "user provisioning complete"
