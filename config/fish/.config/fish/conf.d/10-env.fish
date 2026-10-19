# Environment variables. Always applied - interactive and non-interactive.
#
# Nothing here may depend on PATH: this runs before 20-path.fish.

# ── Locale ───────────────────────────────────────────────────────────────
set -gx LC_ALL en_US.UTF-8
set -gx LANG en_US.UTF-8
set -gx XDG_CONFIG_HOME $HOME/.config

# ── Terminal ─────────────────────────────────────────────────────────────
# ssh to the devbox sets TERM but drops COLORTERM (devbox/scripts/ssh-config.sh),
# so fzf there falls back to 256-colour and TokyoNight's bg+ renders wrong.
# fzf keys its 24-bit decision off this variable. No-op on macOS, where Ghostty
# already sets it. Pairs with `RGB` in terminal-features (tmux.conf), which stops
# tmux downsampling what fzf and neovim emit.
set -gx COLORTERM truecolor

# ── Browser ──────────────────────────────────────────────────────────────
# The devbox is headless, so DISPLAY and WAYLAND_DISPLAY are unset. Some tools
# read that as "no browser here" and give up WITHOUT trying xdg-open - Claude
# Code checks `!$BROWSER && !$DISPLAY && !$WAYLAND_DISPLAY`, which is why
# `claude auth login` printed its URL instead of opening it. Setting BROWSER
# defeats that check. See tools/crates/devbox-open-url/.
#
# A bare command name, not "xdg-open %s": Claude spawns $BROWSER with the URL
# as argv[1] and does not implement the %s convention.
#
# Linux-only via `test -d /proc` rather than `uname`, which costs no fork.
#
# agent-browser's Chromium cannot start its own sandbox: Ubuntu's AppArmor
# blocks the user namespace it needs, and inside pi-safe bubblewrap already
# is the sandbox. pi-safe passes this through (config/pi-safe).
if test -d /proc
    set -gx BROWSER xdg-open
    set -gx AGENT_BROWSER_ARGS --no-sandbox
end

# ── Editor and pager ─────────────────────────────────────────────────────
set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
set -gx MANPAGER "nvim +Man!"
set -gx LESS -R

# ── AWS ──────────────────────────────────────────────────────────────────
# Boot default only. `aws_login` overrides AWS_PROFILE per shell with `set -gx`,
# so each terminal can hold a different active profile.
set -gx AWS_REGION eu-central-1

# ── Node / package managers ──────────────────────────────────────────────
# PNPM_HOME is consumed by 20-path.fish, so it must be set before it. pnpm's
# Linux default, used on macOS too so both share one layout; it is the
# `pnpm add -g` bin dir, and the store is $PNPM_HOME/store (config/pnpm pins
# it for the pi-safe sandbox).
set -gx PNPM_HOME $HOME/.local/share/pnpm
set -gx NPM_CONFIG_USERCONFIG $HOME/.config/npm/.npmrc
set -gx WIREIT_LOGGER metrics
set -gx HUSKY 0
set -gx LEFTHOOK 0

# ── Tools ────────────────────────────────────────────────────────────────
set -gx EZA_CONFIG_DIR $HOME/.config/eza

set -gx OPENCODE_ENABLE_EXA true
set -gx OPENCODE_EXPERIMENTAL_LSP_TOOL true
set -gx OPENCODE_EXPERIMENTAL_WORKSPACES true
set -gx OPENCODE_DISABLE_CLAUDE_CODE_SKILLS true
