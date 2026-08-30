# Load shell secrets from gopass (personal/dotfiles/shell-env)
# GPG agent caches the passphrase after first unlock — prompted once per session max.
# Silently skips if gopass is not installed or the secret does not exist yet.
# Cache lives at ~/.cache/gopass/shell-env — delete it to force a refresh.
if command -q gopass
    set -l gopass_cache ~/.cache/gopass/shell-env

    if not test -f $gopass_cache
        # Cache miss: call gopass, parse output, write cache
        set -l secrets_raw (gopass show personal/dotfiles/shell-env 2>/dev/null)
        if test -n "$secrets_raw"
            mkdir -p ~/.cache/gopass
            set -l cache_tmp $gopass_cache.tmp
            for line in (string split \n $secrets_raw)
                string match -qr '^[A-Za-z_][A-Za-z0-9_]*=' $line; or continue
                set -l parts (string split -m 1 = $line)
                test (count $parts) -eq 2; or continue
                # `string escape` is required: an unescaped value containing
                # spaces becomes a list, and one containing (...) or $ would be
                # evaluated as command substitution on every shell start.
                echo "set -gx $parts[1] "(string escape -- $parts[2]) >>$cache_tmp
                echo "gopass: exported $parts[1]"
            end
            if test -f $cache_tmp
                mv $cache_tmp $gopass_cache
            end
        end
    end

    # Source cache (fast path on subsequent shell starts)
    if test -f $gopass_cache
        source $gopass_cache
    end
end
