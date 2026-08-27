# Load shell secrets from gopass (personal/dotfiles/shell-env)
# GPG agent caches the passphrase after first unlock — prompted once per session max.
# Silently skips if gopass is not installed or the secret does not exist yet.
if command -q gopass
    set -l secrets_raw (gopass show personal/dotfiles/shell-env 2>/dev/null)
    if test -n "$secrets_raw"
        for line in (string split \n $secrets_raw)
            string match -qr '^[A-Za-z_][A-Za-z0-9_]*=' $line; or continue
            set -l parts (string split -m 1 = $line)
            test (count $parts) -eq 2; or continue
            set -gx $parts[1] $parts[2]
            echo "gopass: exported $parts[1]"
        end
    end
end
