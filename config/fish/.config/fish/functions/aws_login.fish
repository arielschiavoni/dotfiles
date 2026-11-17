function aws_login -d "Login to AWS SSO or switch AWS profile"
    # The work is in aws-session (tools/crates/aws-session): pick reads the
    # profiles from ~/.aws/config, ensure asks the CLI for credentials and runs
    # `aws sso login` when the SSO session has ended. This function sets
    # AWS_PROFILE, because only the shell itself can set its variables.
    # Lists the deployer profiles, which is what is used nearly always.
    # `--all` lists every profile; other arguments (--filter GLOB) go to pick.
    set -l args $argv
    if set -l i (contains -i -- --all $args)
        set -e args[$i]
    else if not contains -- --filter $args
        set args --filter '*.deployer' $args
    end
    set -l profile (aws-session pick $args); or return 1
    echo "Selected AWS profile: $profile"
    aws-session ensure $profile; or return 1

    # Exported globally for the current session only, so each terminal can
    # have its own active profile independently
    set -gx AWS_PROFILE $profile
end
