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

    # Check if the selected profile uses SSO by checking for the sso_session key via aws configure get
    if aws configure get sso_session --profile $selected_profile &>/dev/null
        echo "SSO profile detected, checking session..."
        # Use sts get-caller-identity to validate the session — it will auto-refresh
        # if the token is close to expiry; if it fails the session is truly expired
        if not aws sts get-caller-identity --profile $selected_profile &>/dev/null
            echo "Session expired, logging in..."
            aws sso login --profile $selected_profile
            or return 1
        else
            echo "Session still valid."
        end
    end

    # Set AWS_PROFILE globally (exported) for the current session only,
    # so each terminal can have its own active profile independently
    set -gx AWS_PROFILE $selected_profile
end
