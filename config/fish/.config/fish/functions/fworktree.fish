function fworktree -d 'Select a first-level subdir in ~/repos repos, create git worktree, and open tmux session with nvim and fish'
    # Run fd to list only first-level subdirs (exact depth 2) and pipe to fzf
    set repo_dir (fd . --type d --min-depth 2 --max-depth 2 $HOME/repos | fzf )

    # Proceed only if selection made
    if test -n "$repo_dir"
        # Prompt for worktree name/branch
        echo "Enter worktree directory name (also used as branch name): "
        read wt_name

        if test -n "$wt_name"
            # Fetch latest changes from remote
            git -C "$repo_dir" fetch origin

            # Create the worktree
            git -C "$repo_dir" worktree add "$wt_name" -b "$wt_name"

            set worktree_dir "$repo_dir$wt_name"
            set repo_name (basename "$repo_dir")
            set session_name "$repo_name/$wt_name"

            # Create detached tmux session with two windows in worktree_dir
            tmux new-session -d -s "$session_name" -c "$worktree_dir" -n nvim "fish -c 'nvim .'"
            tmux new-window -t "$session_name" -n fish -c "$worktree_dir" fish

            # Select the first window by name (nvim), independent of base-index
            tmux select-window -t "$session_name:nvim"

            # Switch to the new session
            tmux switch-client -t "$session_name"

            echo "Tmux session '$session_name' created successfully in $worktree_dir."
            echo "Press Ctrl-c to close this popup."
        else
            echo "No worktree name provided. Aborting."
        end
    else
        echo "No directory selected. Aborting."
    end
end
