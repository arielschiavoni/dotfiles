# Enable Bedrock integration
# https://code.claude.com/docs/en/amazon-bedrock
set -gx CLAUDE_CODE_USE_BEDROCK 1
# Recommended output token settings for Bedrock
set -gx CLAUDE_CODE_MAX_OUTPUT_TOKENS 4096
set -gx MAX_THINKING_TOKENS 1024
