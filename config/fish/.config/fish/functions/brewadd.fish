function brewadd -d "Install Homebrew packages and declare them in the Brewfile"
    # Installs first and edits the Brewfile only for what installed, so the
    # file never declares a package this Mac does not have.
    argparse c/cask h/help -- $argv; or return 2
    if set -q _flag_help; or test (count $argv) -eq 0
        echo "usage: brewadd [--cask] <name>..."
        echo "Installs each package, then adds it (with a description) to the Brewfile."
        set -q _flag_help; and return 0
        return 2
    end

    set -l brewfile ~/repos/arielschiavoni/dotfiles/install/darwin/Brewfile
    if not test -f $brewfile
        echo "brewadd: no Brewfile at $brewfile" >&2
        return 2
    end

    set -l install_flags
    set -q _flag_cask; and set install_flags --cask
    command brew install $install_flags $argv; or return 2

    set -l failed
    for name in $argv
        # `brew install` picks formula or cask by itself; ask which it was.
        set -l kind --formula
        if set -q _flag_cask; or command brew list --cask $name >/dev/null 2>&1
            set kind --cask
        end

        # user/repo/name needs its tap declared too.
        set -l parts (string split / $name)
        if test (count $parts) -eq 3
            set -l tap $parts[1]/$parts[2]
            if not contains -- $tap (command brew bundle list --file=$brewfile --tap)
                command brew bundle add --file=$brewfile --tap $tap; or set -a failed $tap
            end
        end

        if contains -- $name (command brew bundle list --file=$brewfile $kind)
            echo "brewadd: $name already in the Brewfile"
            continue
        end
        command brew bundle add --file=$brewfile $kind $name; or set -a failed $name
    end

    if set -q failed[1]
        echo "brewadd: installed, but not added to the Brewfile: $failed" >&2
        return 2
    end
end
