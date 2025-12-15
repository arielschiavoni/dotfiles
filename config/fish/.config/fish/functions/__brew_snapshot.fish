function __brew_snapshot -d "Update Brewfile and Brewfile.lock.json with current brew state"
  set -l dotfiles_dir ~/repos/arielschiavoni/dotfiles
  set -l brew_dir $dotfiles_dir/install/darwin
  set -l brewfile $brew_dir/Brewfile
  set -l lockfile $brew_dir/Brewfile.lock.json
  set -l lockfile_tmp $lockfile.tmp

  # Validate target directory exists
  if not test -d $brew_dir
    echo "⚠️ Brewfile directory not found: $brew_dir" >&2
    return 1
  end

  # Collect brew data
  # Use 'command brew' to bypass our wrapper and avoid infinite loops
  set -l taps_json (command brew tap | jq -R -s 'split("\n") | map(select(length > 0)) | map({name: .}) | sort_by(.name)')
  if test $status -ne 0
    echo "⚠️ Brewfile snapshot failed: Error collecting taps" >&2
    return 1
  end

  set -l formulae_json (command brew info --json=v2 --installed | jq '[.formulae[] | select(.installed[0].installed_on_request == true) | {name: .name, version: .installed[0].version, tap: .tap}] | sort_by(.name)')
  if test $status -ne 0
    echo "⚠️ Brewfile snapshot failed: Error collecting formulae" >&2
    return 1
  end

  set -l casks_json (command brew info --json=v2 --installed | jq '[.casks[] | {name: .token, version: .version, tap: .tap}] | sort_by(.name)')
  if test $status -ne 0
    echo "⚠️ Brewfile snapshot failed: Error collecting casks" >&2
    return 1
  end

  # Build JSON object with timestamp
  set -l timestamp (date -u +"%Y-%m-%dT%H:%M:%SZ")
  set -l json_data (jq -n \
    --argjson taps "$taps_json" \
    --argjson formulae "$formulae_json" \
    --argjson casks "$casks_json" \
    --arg generated "$timestamp" \
    '{generated: $generated, taps: $taps, formulae: $formulae, casks: $casks}')

  if test $status -ne 0
    echo "⚠️ Brewfile snapshot failed: Error building JSON" >&2
    return 1
  end

  # Write JSON atomically (temp file + mv to prevent corruption)
  echo "$json_data" | jq '.' > $lockfile_tmp
  if test $status -ne 0
    rm -f $lockfile_tmp
    echo "⚠️ Brewfile snapshot failed: Error writing lock file" >&2
    return 1
  end

  mv $lockfile_tmp $lockfile
  if test $status -ne 0
    rm -f $lockfile_tmp
    echo "⚠️ Brewfile snapshot failed: Error moving lock file" >&2
    return 1
  end

  # Generate Brewfile using brew bundle dump
  # Use 'command brew' to bypass our wrapper and avoid infinite loops
  command brew bundle dump --force --file=$brewfile 2>/dev/null
  if test $status -ne 0
    echo "⚠️ Brewfile snapshot failed: Error running brew bundle dump" >&2
    return 1
  end

  # Rebuild fish bundle cache if the function exists
  # This ensures tool initializations (fnm, zoxide, atuin, starship) stay current
  if functions -q fish_bundle_rebuild
    fish_bundle_rebuild >/dev/null 2>&1
    if test $status -ne 0
      echo "⚠️ Fish bundle rebuild failed" >&2
    end
  end

  return 0
end
