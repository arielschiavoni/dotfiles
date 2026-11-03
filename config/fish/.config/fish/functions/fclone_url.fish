function fclone_url -d 'Paste a repo URL, clone it as bare repo with worktrees and open a tmux session'
    read -P 'repo url> ' -l input
    or return 0
    test -z "$input"; and return 0

    set -l repo (_parse_repo_url "$input")
    or begin
        echo "Not a GitHub repo: $input" >&2
        return 1
    end

    _clone_session $repo
end
