# Fish reads every conf.d/*.fish in natural-sorted order BEFORE this file, and
# reads this file last - so conf.d/ is for configuration, this is for final
# overrides.
#
# Ordering-sensitive snippets are numbered:
#   conf.d/00-brew.fish - Homebrew env (macOS); must precede brew-gnu.fish
#   conf.d/01-mise.fish - mise activation; must precede the tool inits, since
#                         starship/zoxide/atuin are mise-managed in the devbox
#
# Reload everything with `fish_reload` (alt-r, or the `sf` abbreviation).
