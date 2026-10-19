function brewrm -d "Uninstall Homebrew packages and remove them from the Brewfile"
    # Uninstalls first and removes a Brewfile entry only once the package is
    # gone, so a refused uninstall (another package depends on it) keeps both.
    argparse c/cask h/help -- $argv; or return 2
    if set -q _flag_help; or test (count $argv) -eq 0
        echo "usage: brewrm [--cask] <name>..."
        echo "Uninstalls each package, then removes it from the Brewfile."
        set -q _flag_help; and return 0
        return 2
    end

    set -l brewfile ~/repos/arielschiavoni/dotfiles/install/darwin/Brewfile
    if not test -f $brewfile
        echo "brewrm: no Brewfile at $brewfile" >&2
        return 2
    end

    set -l kind_flags
    set -q _flag_cask; and set kind_flags --cask

    set -l kept
    for name in $argv
        # A package that is not installed only needs its entry removed.
        if command brew list $kind_flags $name >/dev/null 2>&1
            command brew uninstall $kind_flags $name
            if command brew list $kind_flags $name >/dev/null 2>&1
                set -a kept $name
                continue
            end
        end
        command brew bundle remove --file=$brewfile $kind_flags $name; or set -a kept $name
    end

    if set -q kept[1]
        echo "brewrm: still installed or still in the Brewfile: $kept" >&2
        return 2
    end
end
