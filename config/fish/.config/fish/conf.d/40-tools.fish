# Prompt, shell history and directory jumping. Interactive shells only.
#
# A `fish -c <cmd>` invocation from a tmux or kitty popup needs no prompt, no
# history daemon and no directory-jump hook. Skipping them removes ~28ms from
# every non-interactive shell.
#
# `exit` at the top level of a sourced file stops that file only; it does not
# terminate the shell. (Inside a *function* it would - see git_worktree_cleanup.)
status is-interactive; or exit

# Requires mise to have activated already (01-mise.fish): in the devbox these
# three are mise-managed and are not on PATH until then.
__init_cached starship init fish --print-full-init
__init_cached zoxide init fish

# NOTE: atuin's init output contains `set -gx ATUIN_SESSION (atuin uuid)`, which
# spawns atuin when the cache is sourced regardless of caching. That is inherent
# to atuin's design and is not avoidable without patching the generated output.
__init_cached atuin init fish
