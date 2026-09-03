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
#
# Deliberately NOT fatal: a single upstream package failure must not stop the
# shell setup below from running. Without this guard `set -e` aborts the script
# and the login shell is left as cloud-init's /bin/bash default, which breaks
# `ssh devbox` entirely (the RemoteCommand tmux is not on bash's PATH).
# The failure is still surfaced by a non-zero exit at the end of this script.
# ---------------------------------------------------------------------------
log "running mise install (skips already-installed tools)"
# PARAM_GithubToken is injected at create time via --param in create.sh.
# It survives the sudo -i invocation because Lima passes PARAM_* via
# --preserve-env. Hard-fail if missing to catch misconfigured creates early.
GITHUB_TOKEN="${PARAM_GithubToken:?GithubToken param not set - re-create with GITHUB_TOKEN exported}"
export GITHUB_TOKEN

MISE_FAILED=0
if ! mise install; then
  MISE_FAILED=1
  log "WARN: mise install reported failures - continuing so shell setup still runs"
fi

# Make mise-managed tools available to the remainder of this script.
eval "$(mise activate bash)"

# ---------------------------------------------------------------------------
# xdg-open - the guest half of the URL opener.
#
# This image is headless, so nothing here provides xdg-open - which is what
# every terminal tool shells out to for links. lazygit's os.openLink defaults
# to `xdg-open {{link}} >/dev/null`, and `nvim gx` and `gh browse` agree, so
# providing this one command name fixes all of them with no per-tool config.
#
# It sends the URL to the devbox-open-url daemon on the Mac over the SSH
# reverse tunnel, and the Mac opens it in the default browser.
# See tools/crates/devbox-open-url/. The Mac half is installed by
# devbox/scripts/create.sh - it cannot be done from here, because this script
# runs inside the guest and cannot reach launchctl on the host.
#
# CARGO_TARGET_DIR: `cargo install` builds in a throwaway temp directory by
# default and discards the cache, which would mean a full rebuild on every
# boot. Pointing it at the repo's shared target/ keeps the cache warm, so a
# no-change boot is a quick re-link. The crate has no dependencies, so even a
# cold build is cheap.
#
# --force: cargo tracks installs in ~/.cargo/.crates2.json as
# "name version (source)" with no content hash. Without --force, an edit to the
# crate under a static 0.1.0 is silently skipped and the VM keeps running the
# old binary.
#
# Not fatal, for the same reason as mise install above.
# ---------------------------------------------------------------------------
log "installing xdg-open (guest half of the URL opener)"
if CARGO_TARGET_DIR="$DOTFILES_DIR/tools/target" \
  cargo install --path "$DOTFILES_DIR/tools/crates/devbox-open-url" \
  --bin xdg-open --locked --force --quiet; then
  log "xdg-open installed"
else
  log "WARN: xdg-open build failed - links will not open on the Mac"
fi

# ---------------------------------------------------------------------------
# tpm - install the tmux plugin manager and the plugins tmux.conf declares.
#
# Must live at the XDG path: that is what tmux.conf sources, and tmux otherwise
# fails with "returned 127". Not fatal, for the same reason as mise install.
# ---------------------------------------------------------------------------
TPM_DIR="$HOME/.config/tmux/plugins/tpm"

if [ ! -d "$TPM_DIR/.git" ]; then
  log "cloning tpm to $TPM_DIR"
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" || log "WARN: tpm clone failed"
else
  log "tpm already cloned"
fi

# install_plugins reads TMUX_PLUGIN_MANAGER_PATH from the server, and only tpm
# sets it while sourcing tmux.conf - so a server started before tpm existed needs
# a reload first, otherwise the install aborts.
if tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$HOME/.config/tmux/tmux.conf" || log "WARN: tmux.conf reload failed"
fi

if [ -x "$TPM_DIR/bin/install_plugins" ]; then
  log "installing tmux plugins (skips already-installed)"
  "$TPM_DIR/bin/install_plugins" || log "WARN: some tmux plugins failed - retry with prefix + I"
fi

# ---------------------------------------------------------------------------
# yazi plugins - install plugins declared in package.toml
# ---------------------------------------------------------------------------
if command -v ya >/dev/null 2>&1; then
  log "installing yazi plugins (skips already-installed)"
  ya pkg install || log "WARN: some yazi plugins failed - retry with: ya pkg install"
else
  log "WARN: ya binary not found - skipping yazi plugin install"
fi

# ---------------------------------------------------------------------------
# gh extensions
# ---------------------------------------------------------------------------
for ext in dlvhdr/gh-dash arielschiavoni/gh-list-repos; do
  ext_name="${ext##*/}"
  if gh extension list 2>/dev/null | grep -q "$ext_name"; then
    log "gh extension already installed: $ext_name"
  else
    log "installing gh extension: $ext"
    gh extension install "$ext" || log "WARN: gh extension install $ext failed"
  fi
done

# ---------------------------------------------------------------------------
# fish shell - register as login shell and set as default
#
# Use mise's `latest` symlink rather than `mise where` directly: the latter
# returns a version-pinned path (.../4.8.1/fish), so a routine fish upgrade
# would leave /etc/passwd pointing at a directory that no longer exists and
# break every login.
# ---------------------------------------------------------------------------
FISH_PATH="$(dirname "$(mise where "aqua:fish-shell/fish-shell")")/latest/fish"

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
# Report deferred mise failures
#
# Exits non-zero so `cloud-init status` shows the error, but only AFTER the
# shell setup above has run - the VM stays usable either way.
# ---------------------------------------------------------------------------
if [ "$MISE_FAILED" -eq 1 ]; then
  log "ERROR: provisioning finished, but some mise tools failed to install."
  log "       Shell setup completed, so the VM is usable. Retry with: mise install"
  exit 1
fi

log "user provisioning complete"
