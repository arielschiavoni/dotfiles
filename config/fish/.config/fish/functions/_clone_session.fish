function _clone_session -a repo_full_name -d 'Create (or reuse) a tmux session that clones org/repo as a bare repo with worktrees'
    set -l url "https://github.com/$repo_full_name"
    echo $url

    # a detached session avoids tmux nesting; fish keeps the window alive after the clone
    if not tmux has-session -t "=$repo_full_name" 2>/dev/null
        tmux new-session -d -s "$repo_full_name" -c "$HOME/repos" -n fish "git_clone_bare $url && fish"
    end
    tmux switch-client -t "=$repo_full_name"
end
