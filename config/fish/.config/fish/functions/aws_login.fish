function aws_login -d "Login to AWS SSO or switch AWS profile"
    # Regenerate the profile cache if:
    # - the cache file doesn't exist yet, OR
    # - ~/.aws/config is newer than the cache (profiles were added/removed), OR
    # - ~/.aws/credentials is newer than the cache (access key profiles changed)
    set -l needs_refresh 0
    if not test -f ~/.aws/profile_cache
        set needs_refresh 1
    else if test ~/.aws/config -nt ~/.aws/profile_cache
        set needs_refresh 1
    else if test -f ~/.aws/credentials; and test ~/.aws/credentials -nt ~/.aws/profile_cache
        set needs_refresh 1
    end

    if test $needs_refresh -eq 1
        echo "Refreshing AWS profile cache..."
        aws configure list-profiles >~/.aws/profile_cache
    end

    set selected_profile (cat ~/.aws/profile_cache | fzf --prompt "Choose active AWS profile:")

    if test -z "$selected_profile"
        echo "No profile selected."
        return 1
    end

    echo "Selected AWS profile: $selected_profile"

    # Check if the selected profile uses SSO (directly or via source_profile chain)
    # by looking for sso_session anywhere in the profile or its source_profile
    if aws configure get sso_session --profile $selected_profile &>/dev/null; or aws configure get source_profile --profile $selected_profile &>/dev/null
        echo "SSO profile detected, checking session..."

        # Validate session using sts get-caller-identity which works for both:
        # - direct SSO profiles (genius.dev.admin)
        # - role profiles chained via source_profile (genius.dev.deployer -> genius.dev.admin)
        # This checks the IAM role credentials (up to 4h) rather than the SSO token (1h),
        # so re-auth is only needed when AWS commands would actually start failing.
        if aws sts get-caller-identity --profile $selected_profile &>/dev/null
            # Session is valid — find remaining time from ~/.aws/cli/cache/
            set -l role_arn (aws configure get role_arn --profile $selected_profile 2>/dev/null)
            set -l sso_role_name (aws configure get sso_role_name --profile $selected_profile 2>/dev/null)
            set -l remaining (python3 ~/.config/fish/scripts/aws_session_remaining.py "$role_arn" "$sso_role_name")
            if test -n "$remaining"
                echo "Session still valid, expires in $remaining."
            else
                echo "Session still valid."
            end
        else
            # IAM credentials expired — need to re-authenticate via SSO browser flow
            # Resolve the root SSO profile to use for login (source_profile chain)
            set -l login_profile $selected_profile
            set -l source (aws configure get source_profile --profile $selected_profile 2>/dev/null)
            if test -n "$source"
                set login_profile $source
            end
            echo "Session expired, logging in with profile '$login_profile'..."
            aws sso login --profile $login_profile
            or return 1
        end
    end

    # Set AWS_PROFILE globally (exported) for the current session only,
    # so each terminal can have its own active profile independently
    set -gx AWS_PROFILE $selected_profile
end
