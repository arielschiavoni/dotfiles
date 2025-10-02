function git_worktree_cleanup -d "Removes worktrees and local branches for worktrees in which the remote branch does not exist"
    function _ask_confirmation
        set -l message $argv[1]
        echo "" # Newline for better spacing
        echo "$message"
        read -P "Type 'yes' to confirm: " response
        if test "$response" = yes
            return 0 # Success (user confirmed)
        else
            echo "Operation cancelled."
            return 1 # Failure (user did not confirm)
        end
    end

    # 1. Fetch and prune remote branches to update local tracking references.
    echo "--- Step 1: Fetching and pruning remote branches ---"
    echo "This ensures local tracking branches reflect the current state of the remote."
    git fetch --all --prune || begin
        echo "Error: Failed to fetch and prune remote branches. Please check your network connection or git configuration." >&2
        exit 1
    end
    echo "Fetch and prune complete."
    echo ""

    echo "--- Step 2: Identifying branches with 'gone' remote branches ---"
    # 2. Capture information about all local branches and the current branch.
    # Get list of local branches whose upstream is gone
    set -l gone_branches (git branch --format='%(refname:short) %(upstream:track)' | awk '$2 == "[gone]" { print $1 }')

    # 3. Identify and propose deletion of worktrees associated with 'gone' remote branches.
    echo "--- Step 3: Identifying worktrees with 'gone' remote branches ---"
    set -l worktrees_to_delete
    set -l identified_worktree_branches

    for worktree_line in (git worktree list --porcelain | grep '^worktree ')
        set -l worktree_path (echo "$worktree_line" | cut -d' ' -f2)

        # Get the branch name for the current worktree.
        # Use -C to run git command within the worktree directory.
        # Redirect stderr to /dev/null as rev-parse might fail if the worktree is broken or branch is already gone.
        set -l wt_branch (git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

        if test -n "$wt_branch"
            if test "$wt_branch" = main
                echo "  Skipping worktree '$worktree_path' because its branch is 'main'."
            else
                # Check if the branch associated with the worktree is marked as '[gone]' in the captured info.
                # This regex ensures we match the specific branch name followed by '[gone]'.
                # string escape --style=regex handles special characters in branch names.
                if echo "$gone_branches" | grep -q "$wt_branch"
                    echo "  Discovered worktree '$worktree_path' linked to 'gone' branch '$wt_branch'."
                    set -a worktrees_to_delete "$worktree_path"
                    set -a identified_worktree_branches "$wt_branch"
                end
            end
        else
            echo "  Could not determine branch for worktree '$worktree_path'. Skipping this worktree."
        end
    end

    if test (count $worktrees_to_delete) -gt 0
        echo ""
        echo "Summary: The following worktrees appear to be associated with 'gone' remote branches:"
        for wt_path in $worktrees_to_delete
            echo "  - $wt_path"
        end
        if _ask_confirmation "Do you want to proceed with deleting these worktrees?"
            echo ""
            echo "--- Deleting identified worktrees ---"
            for wt_path in $worktrees_to_delete
                echo "  Deleting worktree: $wt_path"
                # Use --force to allow removal even if worktree has uncommitted changes or untracked files.
                # This is a destructive operation.
                git worktree remove --force "$wt_path" || echo "    Error: Failed to delete worktree: $wt_path" >&2
            end
            echo "Worktree deletion complete."
        else
            echo "Worktree deletion skipped."
        end
    else
        echo "  No worktrees found linked to 'gone' remote branches."
    end
    echo ""

    # 4. Identify and propose deletion of local branches whose remote counterparts are 'gone' (excluding the current branch).
    echo "--- Step 4: Delete local branches with 'gone' remote branches ---"
    set -l branches_to_delete

    # Get the current Git branch name (abbreviated), or empty if not in a Git repository or on a detached HEAD
    set -l current_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if test -z "$current_branch"
        echo "Warning: Could not determine current branch. Proceeding, but branch deletion safety might be reduced." >&2
    end

    for branch in $gone_branches
        if test "$branch" != "$current_branch"
            echo "  Discovered local branch: '$branch' (its remote has been deleted)."
            set -a branches_to_delete "$branch"
        else
            echo "  Skipping current branch: '$branch' (its remote has been deleted, but cannot delete the active branch)."
        end
    end

    if test (count $branches_to_delete) -gt 0
        echo ""
        echo "Summary: The following local branches appear to have 'gone' remote branches (excluding the current branch):"

        for branch_name in $branches_to_delete
            echo "  - $branch_name"
        end

        if _ask_confirmation "Do you want to proceed with deleting these local branches?"
            echo ""
            echo "--- Deleting identified 'gone' local branches ---"
            for branch_to_delete in $branches_to_delete
                echo "  Deleting branch: $branch_to_delete"
                # Use -D (force delete) to remove even if not fully merged, which is often the case for 'gone' remotes.
                git branch -D "$branch_to_delete" || echo "    Error: Failed to delete branch: $branch_to_delete" >&2
            end
            echo "Local branch deletion complete."
        else
            echo "Local branch deletion skipped."
        end
    else
        echo "  No 'gone' local branches to delete (excluding current branch or those handled by worktree removal)."
    end
    echo ""
    echo "--- Clean-up process complete. ---"

end
