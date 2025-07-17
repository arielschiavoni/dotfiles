function fclone -d 'Present an fzf chooser for a github repo, clone it and create tmux session after selection'
    # create a "queue" also knonw as temporary named pipe where the list of repose will be sent
    # `mktemp -ut` generates a unique name without creating the file.
    set queue (mktemp -ut)
    mkfifo "$queue"

    # run command to list repositories in background and redirect its stdout to the queue
    fish -c "gh list-repos -username arielschiavoni -orgs oneaudi,feature-hub -no-fork >$queue" &

    # Run fzf, reading its input from the named pipe.
    set selection (fzf < "$queue")

    # Only proceed if a selection was made
    if test -n "$selection"
        set matches (string match -r '^(\S+)' -- "$selection")
        set repo_full_name $matches[2]

        # create new window and clone the repository
        set repo_url "https://github.com/$repo_full_name"

        echo $repo_url

        set session_name "$repo_full_name"
        # create new detached session (required to avoid tmux session nesting), in the "~/repos" directory
        # name the default window "fish" and run the git_clone_bare command on it. This command will clone the
        # repository and setup a couple of worktrees. Then fish needs to run after the script completes to avoid tmux exiting the window
        # and the session
        tmux new-session -d -s "$session_name" -c "$HOME/repos" -n fish "git_clone_bare $repo_url && fish"
        # switch to new session
        tmux switch-client -t "$session_name"
    else
        echo "No repository selected. Aborting."
    end
end
