function git_branch_cleanup -d "Cleanup local branches"
    # https://dev.to/iamandrewluca/remove-gone-git-branches-36eh
    # fetch remote branch info (remote branches tracked by local braches could have been deleted and the local references need to updated)
    git fetch --all --prune
    # delete all local branches which track remote branches that have beeen deleted ("gone")
    git branch -vv | awk '/: gone]/{print $2}' | xargs git branch -D
    # delete all branches except the current branch (*) and other branches linked to a worktree (+)
    git branch -vv | grep -vE '^[+*]' | awk '{print $1}' | xargs git branch -D
end
