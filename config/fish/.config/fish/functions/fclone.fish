function fclone -d 'Present an fzf chooser for a github repo, clone it and create a tmux session after selection'
    # Exit codes matter: this runs in a `tmux popup -EE`, which closes the popup
    # on success and keeps it open on failure. A deliberate user cancellation
    # returns 0; only real errors return 1.

    # Named pipe so the (slow) repo listing streams into fzf as it arrives.
    # `mktemp -ut` generates a unique name without creating the file.
    set -l queue (mktemp -ut fclone)
    mkfifo "$queue"; or return 1

    # List repositories in the background, redirecting stdout into the queue
    fish -c "gh list-repos -username arielschiavoni -orgs oneaudi,feature-hub,volkswagen-onehub,accenture-song-naip,anomalyco -no-fork >$queue" &

    set -l selection (fzf <"$queue")
    set -l fzf_status $status

    # The fifo is ours; always clean it up regardless of outcome
    rm -f -- "$queue"

    test $fzf_status -eq 0; or return 0 # fzf cancelled
    test -n "$selection"; or return 0

    set -l matches (string match -r '^(\S+)' -- "$selection")
    set -l repo_full_name $matches[2]
    test -n "$repo_full_name"; or begin
        echo "Error: could not parse a repository name from '$selection'." >&2
        return 1
    end

    set -l repo_url "https://github.com/$repo_full_name"
    echo $repo_url

    # Detached session (avoids tmux session nesting) rooted at ~/repos. The
    # window runs git_clone_bare, then drops into fish so tmux does not close
    # the window (and the session) when the clone completes.
    tmux new-session -d -s "$repo_full_name" -c "$HOME/repos" -n fish "git_clone_bare $repo_url && fish"
    or begin
        echo "Error: failed to create tmux session '$repo_full_name'." >&2
        return 1
    end

    tmux switch-client -t "$repo_full_name"
end
