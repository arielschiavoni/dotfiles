function git_branch_cleanup -d "Delete local branches whose upstream is gone"
    # Optional repo path (defaults to cwd) so callers can target a repo without
    # changing directory. Keeps the interactive `gb!` abbr working unchanged.
    set -l repo $argv[1]
    test -n "$repo"; or set repo .

    # Refresh remote-tracking refs so "[gone]" reflects reality
    git -C $repo fetch --all --prune
    or echo "Warning: fetch --prune failed; 'gone' detection may be stale." >&2

    # Branches checked out in a worktree (incl. the current one) cannot be deleted
    set -l in_use (git -C $repo worktree list --porcelain \
        | string replace -rf '^branch refs/heads/' '')

    for branch in (git -C $repo branch --format='%(refname:short) %(upstream:track)' \
            | awk '$2 == "[gone]" { print $1 }')
        contains -- $branch $in_use; and continue
        git -C $repo branch -D $branch
        or echo "Warning: could not delete branch '$branch'." >&2
    end

    # Best-effort housekeeping: never propagate failure to callers. Chaining this
    # with `&&` used to abort PR setup whenever there was nothing to delete.
    return 0
end
