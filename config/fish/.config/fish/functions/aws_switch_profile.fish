function aws_switch_profile -d "Switch AWS profile"
    # Check if the cache file exists
    if test -f ~/.aws/profile_cache
      # Read profiles from the cache and use fzf to select one
      set selected_profile (cat ~/.aws/profile_cache | fzf --prompt "Choose active AWS profile:")

      if test -n "$selected_profile"
        echo "Selected AWS profile: $selected_profile"
        set -gx AWS_PROFILE $selected_profile
      else
        echo "No profile selected."
      end
    else
      echo "Profile cache file not found. Running `aws configure list-profiles > ~/.aws/profile_cache` to populate it."
      aws configure list-profiles > ~/.aws/profile_cache
      aws_switch_profile
    end
end
