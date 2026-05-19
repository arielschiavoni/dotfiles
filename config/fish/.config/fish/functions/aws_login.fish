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

        # Resolve the root SSO profile (follow source_profile chain once)
        set -l login_profile $selected_profile
        set -l source (aws configure get source_profile --profile $selected_profile 2>/dev/null)
        if test -n "$source"
            set login_profile $source
        end

        # Collect profile metadata for session check
        set -l role_arn (aws configure get role_arn --profile $selected_profile 2>/dev/null)
        set -l sso_role_name (aws configure get sso_role_name --profile $selected_profile 2>/dev/null)
        set -l sso_session (aws configure get sso_session --profile $login_profile 2>/dev/null)

        # Check both the SSO token (in ~/.aws/sso/cache/) AND IAM credentials
        # (in ~/.aws/cli/cache/). Exit code 1 means the SSO token is expired —
        # we must re-authenticate via the browser. Exit code 0 means everything
        # is fine. The script prints a human-readable status line in all cases.
        set -l session_status (python3 ~/.config/fish/scripts/aws_session_remaining.py "$role_arn" "$sso_role_name" "$sso_session")
        set -l script_exit $status

        if test $script_exit -eq 1
            # SSO token expired — must run browser login flow
            echo "SSO token expired, logging in with profile '$login_profile'..."
            aws sso login --profile $login_profile
            or return 1
        else
            # SSO token is valid; also verify IAM credentials with a live call
            # (catches clock skew, revoked tokens, etc.)
            if aws sts get-caller-identity --profile $selected_profile &>/dev/null
                if test -n "$session_status"
                    echo "Session still valid, expires in $session_status."
                else
                    echo "Session still valid."
                end
            else
                # IAM credentials are stale even though SSO token is valid.
                # This can happen after a Homebrew upgrade resets the CLI cache path
                # or when the role session duration (1-4h) has elapsed but the SSO
                # token (8h) hasn't. Re-login refreshes both.
                echo "IAM credentials expired (SSO token still valid), re-authenticating with profile '$login_profile'..."
                aws sso login --profile $login_profile
                or return 1
            end
        end
    end

    # Set AWS_PROFILE globally (exported) for the current session only,
    # so each terminal can have its own active profile independently
    set -gx AWS_PROFILE $selected_profile
end
