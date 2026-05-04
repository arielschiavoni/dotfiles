function git_pr_cleanup -d "Cleanup the current PR worktree, local branch, and tmux session"
    function _abort_with_error
        echo $argv[1] >&2
        read -P "Press Enter to close..." _ignore
    end

    # Parse --force flag
    set -l force 0
    for arg in $argv
        if test "$arg" = --force
            set force 1
        end
    end

    # Ensure we are inside a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        _abort_with_error "Error: Not inside a git repository."
        return 0
    end

    # Get current worktree path and the bare/main worktree path
    set -l current_path (pwd)
    set -l main_worktree (git worktree list --porcelain | awk '/^worktree /{path=$2} /^bare$/{print path; exit}')

    # Refuse to run from the bare/main worktree root
    if test "$current_path" = "$main_worktree"
        _abort_with_error "Error: Cannot run from the main/bare worktree."
        return 0
    end

    # Get current branch name
    set -l branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if test -z "$branch" -o "$branch" = HEAD
        _abort_with_error "Error: Could not determine current branch (detached HEAD?)."
        return 0
    end

    if test "$branch" = main
        _abort_with_error "Error: Refusing to delete the 'main' branch worktree."
        return 0
    end

    # Check for uncommitted changes unless --force is passed
    if test $force -eq 0
        if not git diff --quiet 2>/dev/null; or not git diff --cached --quiet 2>/dev/null
            _abort_with_error "Error: Worktree has uncommitted changes. Commit or stash them first, or use --force to override."
            return 0
        end
    end

    # Get current tmux session name
    set -l session (tmux display-message -p '#S' 2>/dev/null)

    # Show summary and ask for confirmation
    echo ""
    echo "About to clean up:"
    echo "  Worktree : $current_path"
    echo "  Branch   : $branch"
    if test -n "$session"
        echo "  Session  : $session"
    end
    echo ""
    read -P "Type 'yes' to confirm: " response
    if test "$response" != yes
        echo "Operation cancelled."
        return 0
    end

    # Step 1: cd to parent before removing the worktree
    set -l parent (dirname $current_path)
    cd $parent

    echo ""
    echo "Removing worktree $current_path ..."
    if test $force -eq 1
        git worktree remove --force "$current_path" || begin
            echo "Error: Failed to remove worktree." >&2
            return 1
        end
    else
        git worktree remove "$current_path" || begin
            echo "Error: Failed to remove worktree." >&2
            return 1
        end
    end

    # Step 2: delete the local branch
    echo "Deleting branch $branch ..."
    git branch -D "$branch" || echo "Warning: Failed to delete branch '$branch'." >&2

    # Step 3: kill the tmux session — must be last as it closes this popup
    if test -n "$session"
        echo "Killing tmux session $session ..."
        tmux kill-session -t "$session"
    end
end
