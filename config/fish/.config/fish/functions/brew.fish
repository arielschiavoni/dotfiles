function brew -d "Homebrew package manager with automatic Brewfile sync"
  # Commands that should trigger a snapshot
  set -l snapshot_commands install upgrade uninstall reinstall tap untap

  # Call real brew command
  command brew $argv
  set -l brew_status $status

  # If brew succeeded and this was a state-changing command, snapshot
  if test $brew_status -eq 0
    and contains $argv[1] $snapshot_commands
    __brew_snapshot
  end

  # Return original brew exit status (don't mask failures)
  return $brew_status
end
