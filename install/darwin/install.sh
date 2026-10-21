#!/bin/bash
# Install or upgrade this Mac: Homebrew packages, dotfiles, Rust tools, shell
# and macOS settings.
#
# Idempotent: every step checks its own state and converges to what is declared
# here, so the same script sets up a new Mac and upgrades an existing one.
#
# New Mac (no git yet; the Homebrew installer brings the Command Line Tools):
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/arielschiavoni/dotfiles/master/install/darwin/install.sh)"
#
# Afterwards:
#
#   ~/repos/arielschiavoni/dotfiles/install/darwin/install.sh
#
# Runs under macOS's /bin/bash 3.2 on a new Mac, so no bash 4+ features.
set -euo pipefail

DOTFILES_DIR="$HOME/repos/arielschiavoni/dotfiles"
DOTFILES_REPO="https://github.com/arielschiavoni/dotfiles.git"
BREWFILE="$DOTFILES_DIR/install/darwin/Brewfile"

# config/ packages linked into $HOME. pi-safe and cred-broker are Linux-only.
STOW_PACKAGES="aerospace agents atuin btop claude eza fish gh-dash ghostty git
gopass hunk lazygit npm nvim opencode pi pnpm sesh starship tmux tuicr yazi"

# tools/crates built for the Mac. pi-safe and cred-broker are Linux-only.
# devbox-bridge also brings xdg-open, which reaches the same daemon directly.
RUST_TOOLS="aws-session devbox-bridge git-credential-multiaccount"

# Crates removed from tools/, uninstalled from ~/.cargo/bin when present.
RETIRED_RUST_TOOLS="find-old-python"

GH_EXTENSIONS="dlvhdr/gh-dash arielschiavoni/gh-list-repos"

SKIP_PULL=0
SKIP_UPGRADE=0
SKIP_DEFAULTS=0
CLEANUP=0
ARGS=("$@")

usage() {
  cat << 'EOF'
Usage: install.sh [--skip-pull] [--skip-upgrade] [--skip-defaults] [--cleanup]

Installs or upgrades this Mac from the dotfiles repo.

  --skip-pull      Do not touch git. Use when testing local edits, or on a
                   dirty working tree.
  --skip-upgrade   Install what is missing, but upgrade nothing (brew, rustup,
                   gh extensions) and skip the macOS update check.
  --skip-defaults  Leave macOS settings (`defaults write`) alone.
  --cleanup        Uninstall Homebrew packages missing from the Brewfile.
                   Without it they are only listed.
  -h, --help       Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-pull) SKIP_PULL=1 ;;
    --skip-upgrade) SKIP_UPGRADE=1 ;;
    --skip-defaults) SKIP_DEFAULTS=1 ;;
    --cleanup) CLEANUP=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log() { echo "==> $*"; }
warn() { echo "    WARN: $*" >&2; }

# Steps that fail are collected here instead of aborting the run, so one broken
# package does not leave the shell or settings unconfigured. Reported at the end.
FAILED=""
fail() {
  warn "$1"
  FAILED="${FAILED}    - $1"$'\n'
}

if [ "$(uname -s)" != Darwin ]; then
  echo "ERROR: this script is for macOS. The devbox VM uses devbox/scripts/upgrade.sh." >&2
  exit 2
fi

# As root, stow, cargo and Homebrew would write into root's home and chsh would
# change root's shell. The script calls sudo itself where it needs it.
if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: do not run this with sudo - run it as your normal user." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Homebrew. Its installer also installs the Xcode Command Line Tools, which
# provide git for the clone below.
# ---------------------------------------------------------------------------
if [ ! -x /opt/homebrew/bin/brew ]; then
  log "installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

if ! xcode-select -p > /dev/null 2>&1; then
  log "installing the Xcode Command Line Tools - confirm the dialog"
  xcode-select --install || true
  until xcode-select -p > /dev/null 2>&1; do sleep 5; done
fi

# ---------------------------------------------------------------------------
# Dotfiles: clone or pull, then hand over to the repo's copy of this script.
# ---------------------------------------------------------------------------
REPO_SCRIPT="$DOTFILES_DIR/install/darwin/install.sh"
SELF="$(realpath "${BASH_SOURCE[0]:-}" 2> /dev/null || true)"
REEXEC=0

if [ ! -d "$DOTFILES_DIR/.git" ]; then
  log "cloning dotfiles to $DOTFILES_DIR"
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
elif [ "$SKIP_PULL" -eq 0 ]; then
  if ! git -C "$DOTFILES_DIR" diff --quiet \
    || ! git -C "$DOTFILES_DIR" diff --cached --quiet; then
    echo "ERROR: $DOTFILES_DIR has uncommitted changes." >&2
    echo "       Commit or stash them, or re-run with --skip-pull." >&2
    exit 2
  fi

  BEFORE="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
  log "pulling dotfiles"
  git -C "$DOTFILES_DIR" pull --rebase
  AFTER="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
  if [ "$BEFORE" != "$AFTER" ]; then
    git -C "$DOTFILES_DIR" --no-pager log --oneline "$BEFORE..$AFTER" | sed 's/^/    /'
    REEXEC=1
  fi
fi

# A curl-piped run, or a pull that changed this file: continue with the repo
# copy so the script and the files it applies are the same commit.
# --skip-pull ends the recursion.
if [ "$REEXEC" -eq 1 ] || [ "$SELF" != "$REPO_SCRIPT" ]; then
  log "continuing with $REPO_SCRIPT"
  exec /bin/bash "$REPO_SCRIPT" ${ARGS[@]+"${ARGS[@]}"} --skip-pull
fi

# Casks, /etc/shells and chsh need sudo; ask once and keep the ticket fresh
# for the rest of the run.
sudo -v
while true; do
  sudo -n true
  sleep 50
  kill -0 "$$" 2> /dev/null || exit
done 2> /dev/null &

# ---------------------------------------------------------------------------
# Rust. Before brew bundle, which needs cargo for the Brewfile's cargo entries.
# ~/.cargo/bin is put on PATH by config/fish/conf.d/20-path.fish.
# ---------------------------------------------------------------------------
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  log "installing rustup"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path || fail "rustup install"
elif [ "$SKIP_UPGRADE" -eq 0 ]; then
  log "updating rust toolchains"
  "$HOME/.cargo/bin/rustup" update || fail "rustup update"
fi
export PATH="$HOME/.cargo/bin:$PATH"

# ---------------------------------------------------------------------------
# Homebrew packages
#
# Cleanup skips cargo: the tools/crates binaries in ~/.cargo/bin are not in
# the Brewfile and would otherwise be listed for removal.
# ---------------------------------------------------------------------------
BUNDLE_FLAGS=""
if [ "$SKIP_UPGRADE" -eq 0 ]; then
  log "updating Homebrew"
  brew update || fail "brew update"
else
  BUNDLE_FLAGS="--no-upgrade"
fi

log "installing Brewfile packages"
# shellcheck disable=SC2086 # BUNDLE_FLAGS is empty or one word
brew bundle install --file="$BREWFILE" $BUNDLE_FLAGS || fail "brew bundle install"

if [ "$CLEANUP" -eq 1 ]; then
  log "uninstalling packages missing from the Brewfile"
  brew bundle cleanup --file="$BREWFILE" --no-cargo --force || fail "brew bundle cleanup"
  brew cleanup || true
else
  # Exits non-zero when it finds something to list. stdin from /dev/null
  # answers "no" to the `brew cleanup` prompt it ends with.
  brew bundle cleanup --file="$BREWFILE" --no-cargo < /dev/null || true
fi

# Homebrew's npm installs pi once and never upgrades it. Pinned to the Homebrew
# npm, not whichever npm is first on PATH (fnm in interactive shells).
if [ "$SKIP_UPGRADE" -eq 0 ]; then
  log "upgrading pi"
  /opt/homebrew/bin/npm install --global @earendil-works/pi-coding-agent@latest \
    || fail "npm upgrade pi"
fi

# ---------------------------------------------------------------------------
# stow: one package at a time, so a conflicting file blocks only its package.
#
# Broken links into a dotfiles config/ go first: they belong to packages
# removed from the repo, and stow refuses to replace a link it does not own.
# ---------------------------------------------------------------------------
{
  find "$HOME" -maxdepth 1 -type l
  find "$HOME/.config" -maxdepth 3 -type l 2> /dev/null
} | while IFS= read -r link; do
  if [ ! -e "$link" ]; then
    case "$(readlink "$link")" in
      *dotfiles/config/*)
        echo "    removing stale link $link"
        rm "$link"
        ;;
    esac
  fi
done

log "linking config packages into $HOME"
# A real ~/.config keeps stow from folding it into one link to a package.
mkdir -p "$HOME/.config"
for pkg in $STOW_PACKAGES; do
  (cd "$DOTFILES_DIR/config" && stow --target="$HOME" --restow "$pkg") \
    || fail "stow $pkg (move the conflicting file away and re-run)"
done

# ---------------------------------------------------------------------------
# tools/crates
#
# CARGO_TARGET_DIR: `cargo install` otherwise builds in a temp dir and discards
# it, so every run would rebuild from scratch.
# --force: cargo tracks installs as "name version (source)" with no content
# hash, so an edit under the static 0.1.0 would be skipped.
# ---------------------------------------------------------------------------
for tool in $RUST_TOOLS; do
  log "installing $tool"
  CARGO_TARGET_DIR="$DOTFILES_DIR/tools/target" \
    cargo install --path "$DOTFILES_DIR/tools/crates/$tool" \
    --locked --force --quiet || fail "cargo install $tool"
done

INSTALLED_CRATES="$(cargo install --list 2> /dev/null || true)"
for tool in $RETIRED_RUST_TOOLS; do
  if echo "$INSTALLED_CRATES" | grep -q "^$tool "; then
    log "uninstalling retired $tool"
    cargo uninstall "$tool" || fail "cargo uninstall $tool"
  fi
done

# The Mac half of the devbox bridge (links and image paste from the VM).
# --install rewrites the launchd plist and reloads it, picking up a rebuild.
if [ -x "$HOME/.cargo/bin/devbox-bridge" ]; then
  log "loading the devbox-bridge launchd agent"
  "$HOME/.cargo/bin/devbox-bridge" --install || fail "devbox-bridge --install"
fi

# ---------------------------------------------------------------------------
# fish as login shell. /opt/homebrew/bin/fish is a stable symlink across fish
# upgrades.
# ---------------------------------------------------------------------------
FISH_PATH=/opt/homebrew/bin/fish
if [ -x "$FISH_PATH" ]; then
  if ! grep -qxF "$FISH_PATH" /etc/shells; then
    log "registering fish in /etc/shells"
    echo "$FISH_PATH" | sudo tee -a /etc/shells > /dev/null
  fi
  CURRENT_SHELL="$(dscl . -read "/Users/$USER" UserShell | awk '{print $2}')"
  if [ "$CURRENT_SHELL" != "$FISH_PATH" ]; then
    log "setting fish as login shell"
    sudo chsh -s "$FISH_PATH" "$USER" || fail "chsh to fish"
  else
    log "fish already the login shell"
  fi
else
  fail "fish not found at $FISH_PATH"
fi

# ---------------------------------------------------------------------------
# tmux plugins. tpm must live at the XDG path tmux.conf sources.
# ---------------------------------------------------------------------------
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [ ! -d "$TPM_DIR/.git" ]; then
  log "cloning tpm"
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" || fail "tpm clone"
fi

# install_plugins reads TMUX_PLUGIN_MANAGER_PATH from the server, which tpm
# sets only while sourcing tmux.conf.
if tmux list-sessions > /dev/null 2>&1; then
  tmux source-file "$HOME/.config/tmux/tmux.conf" || warn "tmux.conf reload failed"
fi
if [ -x "$TPM_DIR/bin/install_plugins" ]; then
  log "installing tmux plugins"
  "$TPM_DIR/bin/install_plugins" > /dev/null || fail "tmux plugins (retry with prefix + I)"
  if [ "$SKIP_UPGRADE" -eq 0 ]; then
    "$TPM_DIR/bin/update_plugins" all > /dev/null || fail "tmux plugin update"
  fi
fi

# ---------------------------------------------------------------------------
# yazi plugins, pinned by config/yazi/.config/yazi/package.toml
# ---------------------------------------------------------------------------
log "installing yazi plugins"
if ! ya pkg install; then
  rm -rf "$HOME/.cache/yazi/packages"
  ya pkg install || fail "yazi plugins (retry with: ya pkg install)"
fi

# ---------------------------------------------------------------------------
# gh extensions. Needs gh auth or GITHUB_TOKEN; a new Mac has neither until
# gopass is set up, so failures here are expected on the first run.
# ---------------------------------------------------------------------------
INSTALLED_EXTENSIONS="$(gh extension list 2> /dev/null || true)"
for ext in $GH_EXTENSIONS; do
  if ! echo "$INSTALLED_EXTENSIONS" | grep -q "${ext##*/}"; then
    log "installing gh extension $ext"
    gh extension install "$ext" || fail "gh extension install $ext"
  fi
done
if [ "$SKIP_UPGRADE" -eq 0 ] && [ -n "$INSTALLED_EXTENSIONS" ]; then
  log "upgrading gh extensions"
  gh extension upgrade --all || fail "gh extension upgrade"
fi

# ---------------------------------------------------------------------------
# macOS settings
#
# set_default writes only when the value differs and records the domain, so
# only the affected apps are restarted and a converged Mac restarts nothing.
# NSGlobalDomain changes reach most apps only after they relaunch, and the key
# repeat settings only after logging out. A leading -currentHost targets the
# per-machine preferences (ByHost).
# ---------------------------------------------------------------------------
CHANGED_DOMAINS=" "
set_default() {
  local host=""
  if [ "$1" = -currentHost ]; then
    host=-currentHost
    shift
  fi
  local domain="$1" key="$2" type="$3" value="$4" want current
  want="$value"
  if [ "$type" = -bool ]; then
    if [ "$value" = true ]; then want=1; else want=0; fi
  fi
  # shellcheck disable=SC2086 # host is empty or one word
  current="$(defaults $host read "$domain" "$key" 2> /dev/null || true)"
  if [ "$current" != "$want" ]; then
    # shellcheck disable=SC2086
    if defaults $host write "$domain" "$key" "$type" "$value" 2> /dev/null; then
      echo "    $domain $key = $value"
      CHANGED_DOMAINS="$CHANGED_DOMAINS$domain "
    else
      fail "defaults write $domain $key"
    fi
  fi
}

if [ "$SKIP_DEFAULTS" -eq 0 ]; then
  log "applying macOS settings"

  # Keyboard: fastest repeat the System Settings sliders allow, and repeat
  # instead of the accent popup when a key is held (hjkl in vim).
  set_default NSGlobalDomain KeyRepeat -int 2
  set_default NSGlobalDomain InitialKeyRepeat -int 15
  set_default NSGlobalDomain ApplePressAndHoldEnabled -bool false

  # F1-F12 act as function keys; brightness, volume and media need Fn.
  set_default NSGlobalDomain com.apple.keyboard.fnState -bool true

  # Trackpad: tap to click, and three-finger drag to move windows and select
  # text. The three-finger swipes move to four fingers (already the four-finger
  # setting), as System Settings does when three-finger drag is on. Built-in
  # and Bluetooth trackpads keep separate domains; tapBehavior covers the login
  # screen and other users of this Mac.
  for trackpad in com.apple.AppleMultitouchTrackpad \
    com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    set_default "$trackpad" Clicking -bool true
    set_default "$trackpad" TrackpadThreeFingerDrag -bool true
    set_default "$trackpad" TrackpadThreeFingerHorizSwipeGesture -int 0
    set_default "$trackpad" TrackpadThreeFingerVertSwipeGesture -int 0
    set_default "$trackpad" TrackpadFourFingerHorizSwipeGesture -int 2
    set_default "$trackpad" TrackpadFourFingerVertSwipeGesture -int 2
  done
  set_default NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  set_default -currentHost NSGlobalDomain com.apple.mouse.tapBehavior -int 1

  # Text input: no autocorrect or smart punctuation, which corrupt code and
  # commands typed in text fields.
  set_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  set_default NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  set_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  set_default NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  set_default NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

  # Dialogs: expanded save and print panels, save to disk rather than iCloud.
  set_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  set_default NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  set_default NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

  # Finder: hidden files, all extensions, path and status bars, full path in
  # the title, list view, folders first, search the current folder.
  set_default NSGlobalDomain AppleShowAllExtensions -bool true
  set_default com.apple.finder AppleShowAllFiles -bool true
  set_default com.apple.finder ShowPathbar -bool true
  set_default com.apple.finder ShowStatusBar -bool true
  set_default com.apple.finder _FXShowPosixPathInTitle -bool true
  set_default com.apple.finder _FXSortFoldersFirst -bool true
  set_default com.apple.finder FXPreferredViewStyle -string Nlsv
  set_default com.apple.finder FXDefaultSearchScope -string SCcf
  set_default com.apple.finder FXEnableExtensionChangeWarning -bool false
  set_default com.apple.finder NewWindowTarget -string PfHm
  chflags nohidden "$HOME/Library"

  # No .DS_Store files on network shares and USB drives.
  set_default com.apple.desktopservices DSDontWriteNetworkStores -bool true
  set_default com.apple.desktopservices DSDontWriteUSBStores -bool true

  # Dock: auto-hide without delay, no recent apps, and Spaces keep their order
  # (rearranging by recent use breaks keyboard-driven space switching).
  set_default com.apple.dock autohide -bool true
  set_default com.apple.dock autohide-delay -float 0
  set_default com.apple.dock show-recents -bool false
  set_default com.apple.dock mru-spaces -bool false

  # Clicking the wallpaper does not hide every window.
  set_default com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

  # Animations off: windows, sheets, smooth scrolling, Quick Look, focus
  # rings, full screen, Finder, Dock and Mission Control.
  set_default NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
  set_default NSGlobalDomain NSWindowResizeTime -float 0.001
  set_default NSGlobalDomain NSScrollAnimationEnabled -bool false
  set_default NSGlobalDomain NSUseAnimatedFocusRing -bool false
  set_default NSGlobalDomain NSToolbarFullScreenAnimationDuration -float 0
  set_default NSGlobalDomain NSBrowserColumnAnimationSpeedMultiplier -float 0
  set_default NSGlobalDomain NSDocumentRevisionsWindowTransformAnimation -bool false
  set_default NSGlobalDomain QLPanelAnimationDuration -float 0
  set_default com.apple.finder DisableAllAnimations -bool true
  set_default com.apple.dock launchanim -bool false
  set_default com.apple.dock autohide-time-modifier -float 0
  set_default com.apple.dock expose-animation-duration -float 0
  set_default com.apple.dock mineffect -string scale

  # Reduce motion: crossfades instead of the sliding Space switch, the one
  # system animation without its own key. The domain is protected: the write
  # needs Full Disk Access for the terminal, so without it this only warns.
  if [ "$(defaults read com.apple.universalaccess reduceMotion 2> /dev/null || true)" != 1 ]; then
    if defaults write com.apple.universalaccess reduceMotion -bool true 2> /dev/null; then
      echo "    com.apple.universalaccess reduceMotion = true"
      CHANGED_DOMAINS="${CHANGED_DOMAINS}com.apple.universalaccess "
    else
      warn "reduceMotion needs Full Disk Access for the terminal; or turn on"
      warn "System Settings > Accessibility > Motion > Reduce motion by hand"
    fi
  fi

  # Applies keyboard and trackpad settings to the running session.
  case "$CHANGED_DOMAINS" in *" NSGlobalDomain "* | *Multitouch*)
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u \
      || warn "activateSettings failed; log out to apply trackpad and keyboard settings"
    ;;
  esac

  case "$CHANGED_DOMAINS" in *" com.apple.finder "* | *" com.apple.desktopservices "*) killall Finder || true ;; esac
  case "$CHANGED_DOMAINS" in *" com.apple.dock "* | *" com.apple.WindowManager "*) killall Dock || true ;; esac
  case "$CHANGED_DOMAINS" in *" NSGlobalDomain "* | *" com.apple.universalaccess "*) log "log out and back in to apply keyboard and animation settings" ;; esac
fi

# ---------------------------------------------------------------------------
# macOS updates: listed only, since installing one may restart the Mac.
# ---------------------------------------------------------------------------
if [ "$SKIP_UPGRADE" -eq 0 ]; then
  log "checking for macOS updates"
  softwareupdate --list 2>&1 | sed 's/^/    /' || true
  echo "    install with: sudo softwareupdate --install --all --restart"
fi

echo
if [ -n "$FAILED" ]; then
  log "finished, but these steps failed:"
  printf '%s' "$FAILED"
  exit 1
fi
log "Mac up to date. Open a new terminal to pick up shell and PATH changes."
