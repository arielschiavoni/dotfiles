function find_password -d "Fuzzy searches a password in all gopass stores and copies it to the clipboard after selection"
  # disable preview of password :-)
  # gopass show --clip (gopass ls --flat | fzf)
  # redirect output to pbcopy because --clip only copies the first line!
  # gopass show --clip (gopass ls --flat | fzf --preview "gopass show {}")
  gopass show (gopass ls --flat | fzf --preview "gopass show {}") | pbcopy
end

function fish_user_key_bindings -d "Set custom key bindings"
  # https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_default_key_bindings.fish
  fish_default_key_bindings
  # https://fishshell.com/docs/current/interactive.html#vi-mode-commands
  # https://github.com/fish-shell/fish-shell/blob/master/share/functions/fish_vi_key_bindings.fish
  # fish_vi_key_bindings
  bind \cg find_password # TODO: find out why the prompt wait for an CR to finish the command
  bind \cn 'nvim .'
  bind \cv 'env | fzf'
end

function chrome -d "Google Chrome alias"
  open -na "Google Chrome" $argv
end

function kill_port --argument port -d "Kill process using the given port"
  for pid in (lsof -i TCP:$port | awk '/LISTEN/{print $2}')
      echo -n "Found server for port $port with pid $pid: "
      kill -9 $pid; and echo "killed."; or echo "could not kill."
  end
end

function list_node_modules --argument directory -d "Finds all node_modules folders under the given directory"
  # --prune stops traversing once the first node_modules folder was found
  fd --no-ignore -t d node_modules $directory --prune
end

function nuke_node_modules --argument directory -d "Finds and deletes all node_modules folders under the given directory"
  if test -d "$HOME/$directory"
    # --prune stops traversing once the first node_modules folder was found
    # xargs -P is useful to parallelise the deletion of the folders, 0 means maxprocs
    # the -t flag prints the command before running it
    fd --no-ignore -t d node_modules $HOME/$directory --prune | xargs -t -P 0 -I {} rm -rf {}
  else
    echo "The provided directory: $directory is not a subdirectory of $HOME"
    return 1
  end
end

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

function git_branch_cleanup -d "Cleanup local branches"
  # https://dev.to/iamandrewluca/remove-gone-git-branches-36eh
  # fetch remote branch info (remote branches tracked by local braches could have been deleted and the local references need to updated)
  git fetch --all --prune
  # delete all local branches which track remote branches that have beeen deleted ("gone")
  git branch -vv | awk '/: gone]/{print $1}' | xargs git branch -D
  # delete all branches except the current branch (*) and other branches linked to a worktree (+)
  git branch -vv | grep -vE '^[+*]' | awk '{print $1}' | xargs git branch -D
end

function aws_switch_profile -d "Switch AWS profile"
    # Check if the cache file exists
    if test -f ~/.aws/profile_cache
      # Read profiles from the cache and use fzf to select one
      set selected_profile (cat ~/.aws/profile_cache | fzf --prompt "Choose active AWS profile:")

      if test -n "$selected_profile"
        echo "Selected AWS profile: $selected_profile"
        export AWS_PROFILE=$selected_profile
      else
        echo "No profile selected."
      end
    else
      echo "Profile cache file not found. Running `aws configure list-profiles > ~/.aws/profile_cache` to populate it."
      aws configure list-profiles > ~/.aws/profile_cache
      aws_switch_profile
    end
end
