# Must run before the tool-init snippets: in the devbox, starship/zoxide/atuin
# are mise-managed and are not on PATH until mise activates.
#
# Guarded because mise is not installed on the macOS host - Homebrew provides
# those tools there.
if command -q mise
    mise activate fish | source
end
