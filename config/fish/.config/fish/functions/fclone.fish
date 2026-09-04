function fclone -d 'Pick a GitHub org, then a repo within it, clone it and create tmux session after selection'
    # gh-list-repos builds one GraphQL client for its whole process (one
    # token), so it can't fetch orgs that need different accounts in a single
    # call. Picking the org first means only one token is ever needed per
    # invocation - it also skips querying orgs you are not even browsing.
    set -l orgs arielschiavoni oneaudi feature-hub volkswagen-onehub accenture-song-naip anomalyco ASG-SONG

    set -l org (printf '%s\n' $orgs | fzf --prompt 'org> ')
    if test -z "$org"
        echo "No org selected. Aborting."
        return
    end

    # Resolve the token for this org (same gopass mapping git itself uses via
    # git-credential-multiaccount), falling back to the default token when
    # the org has no dedicated secret. Exported via `set -lx` rather than
    # passed as a command-line argument, so it never shows up in `ps`.
    set -lx GH_TOKEN (git-credential-multiaccount token $org)

    # Stream repos straight into fzf via a plain pipe. A named pipe was used
    # here before, but fish opens redirection targets in the parent shell
    # before forking the backgrounded writer, so `gh list-repos >fifo &`
    # deadlocked waiting for a reader that could never start.
    set -l selection
    if test "$org" = arielschiavoni
        set selection (gh list-repos -username arielschiavoni -no-fork | fzf --prompt 'repo> ')
    else
        set selection (gh list-repos -orgs $org -no-fork | fzf --prompt 'repo> ')
    end
    # `gh list-repos` legitimately exits non-zero (broken pipe) whenever fzf
    # closes its input early after the user picks a repo, so a non-zero
    # status here is only a real failure when nothing could be selected.
    set -l list_status $pipestatus[1]

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
    else if test $list_status -ne 0
        echo "Failed to list repositories for '$org' (gh list-repos exited $list_status). Check GH_TOKEN/permissions." >&2
        return 1
    else
        echo "No repository selected. Aborting."
    end
end
