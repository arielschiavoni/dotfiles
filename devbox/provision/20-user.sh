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
# mise needs a token to avoid GitHub's 60 req/hour anonymous limit. Two
# sources, and they cannot collide: on boot Lima runs this under
# `sudo -i --preserve-env=PARAM_*`, which strips GITHUB_TOKEN.
#
#   GITHUB_TOKEN       running this script by hand, in a shell that has it
#   PARAM_GithubToken  on boot; create.sh passes it via --param
#
# Hard-fail before doing any work, to catch a misconfigured create early.
GITHUB_TOKEN="${GITHUB_TOKEN:-${PARAM_GithubToken:-}}"
if [ -z "$GITHUB_TOKEN" ]; then
  log "ERROR: no GitHub token available."
  log "       By hand:    export GITHUB_TOKEN=ghp_... and re-run this script"
  log "       On boot:    re-create the VM with GITHUB_TOKEN exported"
  exit 1
fi
export GITHUB_TOKEN

MISE_FAILED=0
if ! mise install; then
  MISE_FAILED=1
  log "WARN: mise install reported failures - continuing so shell setup still runs"
fi

# Make mise-managed tools available to the remainder of this script.
eval "$(mise activate bash)"

# ---------------------------------------------------------------------------
# xdg-open and xclip - the guest halves of the host bridge.
#
# This image is headless and provides neither command:
#
#   xdg-open  what lazygit, `nvim gx` and `gh browse` shell out to for links
#   xclip     what opencode and Claude Code shell out to for a pasted image
#
# Both talk to the devbox-bridge daemon on the Mac over the SSH reverse tunnel.
# devbox/scripts/create.sh installs the Mac half; it cannot be done from here,
# which runs inside the guest with no launchctl on the host.
# See tools/crates/devbox-bridge/.
#
# --features guest: gates xclip so install/darwin/install.sh, which builds every
# crate with default features, keeps a fake xclip out of ~/.cargo/bin on the Mac.
#
# CARGO_TARGET_DIR: `cargo install` otherwise builds in a throwaway temp dir and
# discards the cache, meaning a full rebuild on every boot.
#
# --force: cargo tracks installs as "name version (source)" with no content
# hash, so an edit under a static 0.1.0 is silently skipped.
#
# Not fatal, for the same reason as mise install above.
# ---------------------------------------------------------------------------
log "installing xdg-open and xclip (guest halves of the host bridge)"
if CARGO_TARGET_DIR="$DOTFILES_DIR/tools/target" \
  cargo install --path "$DOTFILES_DIR/tools/crates/devbox-bridge" \
  --bin xdg-open --bin xclip --features guest --locked --force --quiet; then
  log "xdg-open and xclip installed"
else
  log "WARN: devbox-bridge build failed - links and image paste will not work"
fi

# ---------------------------------------------------------------------------
# git-credential-multiaccount - git's credential helper (config/git sets
# `helper = multiaccount`); also what conf.d/35-github-token.fish shells out
# to for GITHUB_TOKEN. Deferred rather than fatal, like mise install.
# ---------------------------------------------------------------------------
CARGO_FAILED=0
log "installing git-credential-multiaccount"
if CARGO_TARGET_DIR="$DOTFILES_DIR/tools/target" \
  cargo install --path "$DOTFILES_DIR/tools/crates/git-credential-multiaccount" \
  --locked --force --quiet; then
  log "git-credential-multiaccount installed"
else
  CARGO_FAILED=1
  log "WARN: git-credential-multiaccount build failed - git auth and GITHUB_TOKEN will not work"
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
if [ "$MISE_FAILED" -eq 1 ] || [ "$CARGO_FAILED" -eq 1 ]; then
  log "ERROR: provisioning finished, but some steps failed."
  log "       Shell setup completed, so the VM is usable."
  [ "$MISE_FAILED" -eq 1 ] && log "       mise tools - retry with: mise install"
  [ "$CARGO_FAILED" -eq 1 ] && log "       git-credential-multiaccount - retry the cargo install above"
  exit 1
fi

log "user provisioning complete"
