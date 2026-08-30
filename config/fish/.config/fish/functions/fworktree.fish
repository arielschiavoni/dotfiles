function fworktree -d 'Select a repo in ~/repos, create a git worktree, and open a tmux session with nvim and fish'
    # Exit codes matter: this runs in a `tmux popup -EE`, which closes the popup
    # on success and keeps it open on failure. So a deliberate user cancellation
    # returns 0 (popup closes quietly), and only real errors return 1 (popup
    # stays up so the message is readable).

    # List only first-level subdirs (exact depth 2) and pipe to fzf
    set -l repo_dir (fd . --type d --min-depth 2 --max-depth 2 $HOME/repos | fzf)
    or return 0 # fzf cancelled

    test -n "$repo_dir"; or return 0

    set -l base_branch (git -C "$repo_dir" branch --format='%(refname:short)' | fzf --prompt="Select base branch: ")
    or return 0 # fzf cancelled

    test -n "$base_branch"; or return 0

    read -P "Worktree name (also used as branch name): " wt_name
    test -n "$wt_name"; or return 0

    # Fetch latest changes from remote
    git -C "$repo_dir" fetch origin
    or begin
        echo "Error: failed to fetch from origin." >&2
        return 1
    end

    git -C "$repo_dir" worktree add "$wt_name" -b "$wt_name" "$base_branch"
    or begin
        echo "Error: failed to create worktree '$wt_name' from '$base_branch'." >&2
        return 1
    end

    set -l worktree_dir "$repo_dir$wt_name"
    set -l repo_name (basename "$repo_dir")
    set -l session_name "$repo_name/$wt_name"

    # Detached session (avoids tmux session nesting) with two windows
    tmux new-session -d -s "$session_name" -c "$worktree_dir" -n nvim "fish -c 'nvim .'"
    tmux new-window -t "$session_name" -n fish -c "$worktree_dir" fish

    # Select the first window by name, independent of base-index
    tmux select-window -t "$session_name:nvim"
    tmux switch-client -t "$session_name"

    echo "Tmux session '$session_name' created in $worktree_dir."
end
