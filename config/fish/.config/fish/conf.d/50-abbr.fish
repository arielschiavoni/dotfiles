# Abbreviations. Interactive shells only - abbreviations expand as you type and
# have no effect in `fish -c`.
#
# NOTE: `docker` is deliberately NOT here. It lives in functions/docker.fish so
# that it also works in non-interactive shells; an alias defined behind this
# guard would silently vanish for scripts and tmux popups.
status is-interactive; or exit

# ── Editors and package managers ─────────────────────────────────────────
abbr --add --global v nvim
abbr --add --global n npm
abbr --add --global p pnpm

# ── Modern replacements for coreutils ────────────────────────────────────
abbr --add --global cat bat
abbr --add --global ls 'eza --long --all --icons auto'
abbr --add --global la 'eza --long --all --icons auto'
abbr --add --global lt 'eza --tree --all --level 2 --icons auto'
abbr --add --global tree 'eza --tree --all --level 2 --icons auto'

# ── Shell ────────────────────────────────────────────────────────────────
abbr --add --global sf fish_reload

# ── Git ──────────────────────────────────────────────────────────────────
abbr --add --global gclb git_clone_bare
abbr --add --global gc 'git commit -v -m'
abbr --add --global gpu 'git push -u origin HEAD'
abbr --add --global gwl 'git worktree list'
abbr --add --global gwa 'git worktree add'
abbr --add --global gjm 'git jump merge'
abbr --add --global gw! git_worktree_cleanup
abbr --add --global gb! git_branch_cleanup
