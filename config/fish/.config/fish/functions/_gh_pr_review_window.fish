function _gh_pr_review_window -d "Prepare the PR worktree, then hand the tmux window over to nvim"
    # Runs as the initial pane command of the session created by `gh_pr_review`.
    # All inputs arrive as session environment variables (see `tmux -e` there),
    # so there is no shell quoting to get wrong.

    set -l session (tmux display-message -p '#S')

    function _fail -a message
        echo "" >&2
        echo "  ── PR SETUP FAILED ──────────────────────────────" >&2
        echo "  $message" >&2
        echo "  $GH_PR_REPO#$GH_PR_NUMBER  ($GH_PR_BRANCH)" >&2
        echo "  ─────────────────────────────────────────────────" >&2
        echo "" >&2
        # Make the failure impossible to miss from any other window.
        tmux rename-window -t "$TMUX_PANE" "SETUP FAILED"
        tmux display-message -d 4000 "gh_pr_review: $GH_PR_REPO#$GH_PR_NUMBER setup failed"
        # Leave a usable shell with the error still on screen.
        cd "$GH_PR_REPO_PATH"
        exec fish
    end

    if not test -d "$GH_PR_WORKTREE"
        git -C "$GH_PR_REPO_PATH/main" pull --ff-only
        or echo "Warning: could not fast-forward main; continuing." >&2

        # Also performs `fetch --all --prune`, so origin/* refs are fresh below.
        git_branch_cleanup "$GH_PR_REPO_PATH"

        set -l wt (basename "$GH_PR_WORKTREE")
        git -C "$GH_PR_REPO_PATH" worktree add $wt -b "$GH_PR_BRANCH" "origin/$GH_PR_BRANCH"
        or git -C "$GH_PR_REPO_PATH" worktree add $wt "$GH_PR_BRANCH" # branch already local
        or _fail "git worktree add failed (see output above)."
    end

    cd "$GH_PR_WORKTREE"; or _fail "worktree directory missing after creation."

    # The worktree exists now, so spawning the second window here cannot race
    # against its creation.
    if test "$GH_PR_MODE" = review
        tmux new-window -d -t "$session" -n tuicr -c "$GH_PR_WORKTREE" \
            "tuicr pr '$GH_PR_REPO#$GH_PR_NUMBER'; fish"
        tmux set-option -w -t "$session:tuicr" remain-on-exit failed
        tmux select-window -t "$session:tuicr"
    end

    switch "$GH_PR_MODE"
        case review
            nvim .
        case '*'
            # Prefer the local base branch (just fast-forwarded); fall back to the
            # remote ref for PRs stacked on a branch not checked out locally.
            set -l base "$GH_PR_BASE"
            git rev-parse --verify --quiet "refs/heads/$base" >/dev/null
            or set base "origin/$GH_PR_BASE"
            nvim -c ":DiffviewOpen $base...$GH_PR_BRANCH --imply-local"
    end

    # nvim exited or crashed — keep the session alive with a shell in the worktree.
    exec fish
end
