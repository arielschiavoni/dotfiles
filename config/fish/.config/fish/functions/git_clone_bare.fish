function git_clone_bare --argument url -d "Create a bare git clone repository"
  # get repo name from url
  set -l repo_name (string match -r -g '([^/]+)$' $url)

  # create bare clone
  git clone --bare $url $repo_name

  # cd into new repo
  cd $repo_name

  # configure remote.origin.fetch to properly pull/push with bare repos (it does not work out of the box)
  echo "configuring git 'remote.origin.fetch' ..."
  # https://github.com/ThePrimeagen/git-worktree.nvim#troubleshooting
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git config --get remote.origin.fetch

  # show empty worktrees
  echo "worktrees ..."
  git worktree list

  # identify the default branch
  echo "identifing default branch ..."
  set -l head (git remote show origin | grep 'HEAD')
  set -l default_branch (string match -r -g '(\w+)$' $head)
  echo "the default branch is: $default_branch"

  # create work tree for the default branch
  echo "creating worktree for $default_branch branch"
  git worktree add $default_branch $default_branch

  # set upstream for the default branch
  echo "setting upstream to origin"
  git fetch
  git branch --set-upstream-to=origin/$default_branch $default_branch

  # list worktrees
  echo "worktrees ..."
  git worktree list

  # navigate to the work tree
  cd $default_branch
  # pull to show up to date message
  git pull

  echo "done! ✅"
end
