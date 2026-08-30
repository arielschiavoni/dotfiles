# TokyoNight colours for fish and fzf.
# https://github.com/folke/tokyonight.nvim/blob/main/extras/fish/tokyonight_night.fish
#
# Deliberately NOT guarded by `status is-interactive`: fworktree, fclone and
# find_password run fzf from a non-interactive `fish -c`, so FZF_DEFAULT_OPTS
# must be set there too. Setting the fish_color_* variables costs ~1ms, which is
# not worth splitting this file in two to avoid.

# ── Palette ──────────────────────────────────────────────────────────────
set -l foreground c0caf5
set -l selection 283457
set -l comment 565f89
set -l red f7768e
set -l orange ff9e64
set -l yellow e0af68
set -l green 9ece6a
set -l purple 9d7cd8
set -l cyan 7dcfff
set -l pink bb9af7

# ── Syntax highlighting ──────────────────────────────────────────────────
set -g fish_color_normal $foreground
set -g fish_color_command $cyan
set -g fish_color_keyword $pink
set -g fish_color_quote $yellow
set -g fish_color_redirection $foreground
set -g fish_color_end $orange
set -g fish_color_option $pink
set -g fish_color_error $red
set -g fish_color_param $purple
set -g fish_color_comment $comment
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $green
set -g fish_color_escape $pink
set -g fish_color_autosuggestion $comment

# ── Completion pager ─────────────────────────────────────────────────────
set -g fish_pager_color_progress $comment
set -g fish_pager_color_prefix $cyan
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $comment
set -g fish_pager_color_selected_background --background=$selection

# ── fzf ──────────────────────────────────────────────────────────────────
# A fish list; fish joins non-path variables with spaces when exporting, so this
# reaches fzf as a normal option string.
#
# Deliberately does NOT append to an inherited $FZF_DEFAULT_OPTS. The previous
# `export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS ..."` re-appended the whole option
# set in every nested shell, so the value grew without bound - 437 chars at depth
# 1, 875 at depth 2, 1313 at depth 3. tmux runs fish inside fish, and popups run
# `fish -c` inside that, so this compounded quickly. This file owns fzf theming;
# assigning outright is idempotent.
set -gx FZF_DEFAULT_OPTS \
    --highlight-line \
    --info=inline-right \
    --ansi \
    --layout=reverse \
    --border=none \
    --color=bg+:#283457 \
    --color=bg:#16161e \
    --color=border:#27a1b9 \
    --color=fg:#c0caf5 \
    --color=gutter:#16161e \
    --color=header:#ff9e64 \
    --color=hl+:#2ac3de \
    --color=hl:#2ac3de \
    --color=info:#545c7e \
    --color=marker:#ff007c \
    --color=pointer:#ff007c \
    --color=prompt:#2ac3de \
    --color=query:#c0caf5:regular \
    --color=scrollbar:#27a1b9 \
    --color=separator:#ff9e64 \
    --color=spinner:#ff007c
