function aws_login -d "Login to AWS SSO or switch AWS profile"
    # The work is in aws-session (tools/crates/aws-session): pick reads the
    # profiles from ~/.aws/config, ensure asks the CLI for credentials and runs
    # `aws sso login` when the SSO session has ended. This function sets
    # AWS_PROFILE, because only the shell itself can set its variables.
    set -l profile (aws-session pick $argv); or return 1
    echo "Selected AWS profile: $profile"
    aws-session ensure $profile; or return 1

    # Exported globally for the current session only, so each terminal can
    # have its own active profile independently
    set -gx AWS_PROFILE $profile
end
