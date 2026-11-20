function rex_upgrade -d 'Install or upgrade Rex from a DMG through a local Homebrew cask'
    argparse h/help -- $argv; or return 2

    if set -q _flag_help; or test (count $argv) -ne 1
        echo 'Usage: rex_upgrade PATH_TO_DMG'
        echo 'Example: rex_upgrade ~/Downloads/Rex-0.1.0-2064.dmg'
        echo
        echo 'Writes the ariel/local/rex cask for the DMG, then installs or'
        echo 'upgrades it with brew. Rex is quit first if it is running.'
        set -q _flag_help; and return 0
        return 2
    end

    set -l dmg (path resolve -- $argv[1])
    if not test -f "$dmg"
        echo "rex_upgrade: no such file: $argv[1]" >&2
        return 2
    end

    # Rex builds are distributed as Rex-<version>-<build>.dmg; the cask version
    # keeps both, so brew sees every new build as an upgrade.
    set -l parts (string match -r '^Rex-(\d+(?:\.\d+)+)-(\d+)\.dmg$' -- (path basename $dmg))
    if not set -q parts[3]
        echo 'rex_upgrade: expected a file named like Rex-0.1.0-2064.dmg' >&2
        return 2
    end
    set -l rex_version "$parts[2],$parts[3]"

    # The path is written into a Ruby string and a file:// URL.
    if string match -qr '["\\\\#\s]' -- $dmg
        echo "rex_upgrade: move the DMG to a path without spaces or quotes: $dmg" >&2
        return 2
    end

    # brew checks the download against this checksum.
    set -l sha256 (shasum -a 256 $dmg | string split -f1 ' '); or return 2

    # brew installs casks into /Applications with the rights it is granted on
    # this Mac. Copying the app directly gets "Permission denied" there, so the
    # DMG is packaged as a cask in a local tap. Taps live in brew's repository,
    # outside the dotfiles; `tap-new --no-git` creates a plain directory.
    set -l tap ariel/local
    set -l tap_dir (brew --repository)/Library/Taps/ariel/homebrew-local
    if not test -d $tap_dir
        brew tap-new --no-git $tap >/dev/null; or return 2
    end
    # Homebrew refuses to load casks from a tap it has not been told to trust.
    brew trust $tap >/dev/null; or return 2

    mkdir -p $tap_dir/Casks; or return 2
    # `uninstall quit:` makes brew quit the running app before replacing it.
    printf '%s\n' \
        'cask "rex" do' \
        "  version \"$rex_version\"" \
        "  sha256 \"$sha256\"" \
        '' \
        "  url \"file://$dmg\"" \
        '  name "Rex"' \
        '  desc "Terminal multiplexer"' \
        '  homepage "https://www.superlogical.com/rex"' \
        '' \
        '  depends_on macos: :sequoia' \
        '' \
        '  app "Rex.app"' \
        '' \
        '  uninstall quit: "com.superlogical.rex"' \
        end >$tap_dir/Casks/rex.rb; or return 2

    # The cask comes from a local file, so updating brew itself adds nothing.
    if brew list --cask $tap/rex >/dev/null 2>&1
        HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --cask $tap/rex; or return 2
    else
        HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask $tap/rex; or return 2
    end

    # A notarized build passes; anything else should not be launched.
    if not codesign --verify --deep --strict /Applications/Rex.app
        echo 'rex_upgrade: /Applications/Rex.app failed signature verification' >&2
        return 2
    end
    /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' /Applications/Rex.app/Contents/Info.plist \
        | string replace -r '^' 'Installed Rex build '
end
