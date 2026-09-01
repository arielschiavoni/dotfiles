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

# ── Editor and pager ─────────────────────────────────────────────────────
set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
set -gx MANPAGER "nvim +Man!"
set -gx LESS -R

# ── AWS ──────────────────────────────────────────────────────────────────
# Boot default only. `aws_login` overrides AWS_PROFILE per shell with `set -gx`,
# so each terminal can hold a different active profile.
set -gx AWS_PROFILE renderman-dev
set -gx AWS_REGION eu-central-1

# ── Node / package managers ──────────────────────────────────────────────
# PNPM_HOME is consumed by 20-path.fish, so it must be set before it.
set -gx PNPM_HOME $HOME/pnpm
set -gx NPM_CONFIG_USERCONFIG $HOME/.config/npm/.npmrc
set -gx WIREIT_LOGGER metrics
set -gx HUSKY 0

# ── Tools ────────────────────────────────────────────────────────────────
set -gx EZA_CONFIG_DIR $HOME/.config/eza

set -gx OPENCODE_ENABLE_EXA true
set -gx OPENCODE_EXPERIMENTAL_LSP_TOOL true
set -gx OPENCODE_EXPERIMENTAL_WORKSPACES true
set -gx OPENCODE_DISABLE_CLAUDE_CODE_SKILLS true
