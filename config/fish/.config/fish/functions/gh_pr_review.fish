function gh_pr_review -d "Open a GitHub PR in a dedicated tmux session backed by a git worktree"
    # Entry point for the gh-dash `d` (diff) and `c` (code review) keybindings.
    #
    # Deliberately does NO git I/O: gh-dash blocks while a custom command runs,
    # so all fetching/worktree creation happens inside the tmux window via
    # `_gh_pr_review_window`. Data is handed over with `tmux -e` so the window
    # command string needs zero shell quoting.

    argparse --name=gh_pr_review 'mode=' 'repo=' 'pr=' 'branch=' 'base=' 'path=' -- $argv
    or return 1

    set -l mode $_flag_mode
    test -n "$mode"; or set mode diff

    for required in repo pr branch base path
        # Double dereference: resolve the name "_flag_<required>", then its value
        set -l flag "_flag_$required"
        if test -z "$$flag"
            echo "gh_pr_review: missing --$required" >&2
            return 1
        end
    end

    set -l repo_full $_flag_repo # e.g. oneaudi/falcon-renderer
    set -l pr $_flag_pr
    set -l head $_flag_branch # e.g. feat/webart-22547-...
    set -l base $_flag_base # e.g. main
    set -l repo_path (string replace -r '^~' $HOME -- $_flag_path)

    # Cheap checks only — these are the errors gh-dash can report instantly.
    if not test -d "$repo_path/main"
        echo "gh_pr_review: '$repo_path/main' not found; is $repo_full cloned (bare layout)?" >&2
        return 1
    end

    set -l repo_name (string split -- / $repo_full)[-1]
    set -l wt_name "$pr"_(string replace -a / _ -- $head)
    set -l session "$repo_name/$wt_name"

    # Already open? Just go there instead of failing on `worktree add`.
    if tmux has-session -t "=$session" 2>/dev/null
        tmux switch-client -t "$session"
        return 0
    end

    tmux new-session -d -s "$session" -c "$repo_path" -n nvim \
        -e GH_PR_REPO="$repo_full" \
        -e GH_PR_NUMBER="$pr" \
        -e GH_PR_BRANCH="$head" \
        -e GH_PR_BASE="$base" \
        -e GH_PR_REPO_PATH="$repo_path" \
        -e GH_PR_WORKTREE="$repo_path/$wt_name" \
        -e GH_PR_MODE="$mode" \
        _gh_pr_review_window
    or return 1

    # Backstop: if the pane's command dies outright, keep it visible with its output.
    tmux set-option -w -t "$session:nvim" remain-on-exit failed

    # Switch immediately so the git setup output is watched live.
    tmux switch-client -t "$session"
end
