function github_token_pick --description "Pick a GITHUB_TOKEN from gopass via fzf"
    set -l prefix personal/dotfiles/github-tokens

    # `gopass ls --flat` prints full secret paths; strip the prefix so we pass a
    # bare key (e.g. "ASG-SONG") to git-credential-multiaccount. Passing the
    # full path made it look up <prefix>/<prefix>/<key> (miss -> silent fallback
    # to `default`) and write a nested cache dir instead of a cache file.
    set -l keys (gopass ls --flat $prefix | string trim | string replace "$prefix/" "")
    if test (count $keys) -eq 0
        echo "No entries found under $prefix" >&2
        return 1
    end

    set -l key (printf '%s\n' $keys | fzf --prompt=" GITHUB_TOKEN> " \
        --layout=reverse \
        --no-sort)

    if test -z "$key"
        echo "No token selected."
        return 1
    end

    set -gx GITHUB_TOKEN (git-credential-multiaccount token $key)
    set -g __github_token_current_key $key
    echo "GITHUB_TOKEN set to key: $key"
end
