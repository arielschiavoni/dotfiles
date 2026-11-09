# GitHub Packages login for the npm CLI: the default read:packages token,
# read from gopass on each call and set only for the npm/npx process, as
# npm's env config for the registry's _authToken. pnpm reads its tokens
# itself (tokenHelper in ~/.config/pnpm/auth.ini).
if command -q gopass
    function __npm_with_packages_token
        set -l token (gopass show -o personal/dotfiles/npm-tokens/default 2>/dev/null)
        env "npm_config_//npm.pkg.github.com/:_authToken=$token" $argv
    end

    function npm --wraps npm
        __npm_with_packages_token npm $argv
    end

    function npx --wraps npx
        __npm_with_packages_token npx $argv
    end
end
