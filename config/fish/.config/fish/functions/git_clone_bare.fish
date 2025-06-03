function git_clone_bare --argument url -d "Create a bare git clone repository"
    # Helper function to identify the default branch from the current repository
    function _identify_default_branch
        set head (git remote show origin | grep 'HEAD')
        set default_branch_name (string match -r -g '(\w+)$' $head)
        echo $default_branch_name
    end

    set repo_path (string replace "https://github.com/" "" -- "$url")
    set repo_org (string split '/' -- "$repo_path")[1]
    set repo_name (string split '/' -- "$repo_path")[2]
    set repo_location "$HOME/repos/$repo_org/$repo_name"
    # Initialize default_branch variable
    set default_branch ""

    if test -d "$repo_location"
        echo "The repo is already cloned in $repo_location"
        cd $repo_location
        set default_branch (_identify_default_branch)
    else
        mkdir -p $repo_location
        # cd into new repo
        cd $repo_location
        # Moves all the administrative git files (a.k.a $GIT_DIR) under .bare directory.
        # Plan is to create worktrees as siblings of this directory.
        # Example targeted structure:
        # .bare
        # main
        # new-awesome-feature
        # hotfix-bug-12
        # ...
        git clone --bare "$url" .bare
        echo "gitdir: ./.bare" >.git

        # Explicitly sets the remote origin fetch so we can fetch remote branches
        echo "configuring git 'remote.origin.fetch' ..."
        # https://github.com/ThePrimeagen/git-worktree.nvim#troubleshooting
        git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
        # Gets all branches from origin
        git fetch origin

        set default_branch (_identify_default_branch) # Reuse logic

        # create worktree for the default branch
        echo "creating worktree for $default_branch branch"
        git worktree add $default_branch $default_branch
        # create worktree for review
        git worktree add review -b review

        # set upstream for the default branch
        echo "setting upstream to origin"
        # This fetch is implicitly on origin because it's the only remote,
        # and needed before setting upstream if new branches were pulled.
        git fetch
        git branch --set-upstream-to=origin/$default_branch $default_branch
    end

    # Navigate to the default worktree, pull changes, and success message
    # Ensure default_branch was successfully identified
    if test -n "$default_branch"
        echo "worktrees ..."
        git worktree list

        # navigate to the worktree
        echo "navigating to '$default_branch' worktree and pulling latest changes..."
        cd "$default_branch"
        git pull
        echo "done! ✅"
    else
        echo "Error: Could not determine default branch. Skipping final pull."
    end

end
