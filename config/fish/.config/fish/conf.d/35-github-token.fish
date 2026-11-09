# Per-directory GITHUB_TOKEN, for tools that read it from the shell (gh CLI,
# scripts, opencode) rather than through git's credential helper.
#
# Resolution (gopass lookup, default fallback, disk cache) lives in the
# git-credential-multiaccount binary (tools/crates/git-credential-multiaccount)
# so it isn't duplicated here - this just picks the org key from $PWD and asks
# that binary to resolve it. The same binary is git's global credential
# helper, so both consumers agree on which token is active.
#
# Cache lives at ~/.cache/gopass/github-token-<org>; `fish_reload` clears it.
if command -q git-credential-multiaccount
    set -g __github_token_current_key ""

    function __github_token_update_for_pwd --on-variable PWD
        set -l m (string match -r -- "^$HOME/repos/([^/]+)" $PWD)
        set -l key default
        if test (count $m) -ge 2
            set key $m[2]
        end

        if test "$key" = "$__github_token_current_key"
            return
        end
        set -g __github_token_current_key $key

        set -gx GITHUB_TOKEN (git-credential-multiaccount token $key)
    end

    # --on-variable only fires on change, so run once for the startup PWD.
    __github_token_update_for_pwd
end
