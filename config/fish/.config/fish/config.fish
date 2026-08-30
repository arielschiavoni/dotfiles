# Fish reads every conf.d/*.fish in natural-sorted order BEFORE this file, and
# reads this file last. All configuration lives in conf.d/; this file is only for
# final overrides, and is intentionally empty.
#
# The numeric prefix IS the contract - it encodes load order, not category:
#
#   00-brew.fish     Homebrew env (macOS). MUST precede 20-path.
#   01-mise.fish     mise activation. MUST precede 40-tools, since in the devbox
#                    starship/zoxide/atuin are mise-managed and are not on PATH
#                    until mise activates.
#   10-env.fish      Environment variables. May not depend on PATH.
#   20-path.fish     Every PATH entry, in one explicit order.
#   30-secrets.fish  gopass-backed secrets.
#   40-tools.fish    [interactive] prompt, history, directory jumping.
#   50-abbr.fish     [interactive] abbreviations.
#   60-theme.fish    Colours for fish and fzf.
#
# Files marked [interactive] start with `status is-interactive; or exit`, which
# stops that file only - it does not terminate the shell. This keeps `fish -c`
# invocations from tmux and kitty popups from paying for a prompt and a history
# daemon they will never display.
#
# Functions live in functions/, one per file, and are lazily autoloaded on first
# call. Do not move them here: defining all of them eagerly costs ~21ms on every
# shell start, and would also break `funced`/`funcsave` and edit-without-reload.
#
# Reload everything with `fish_reload` (alt-r, or the `sf` abbreviation).
