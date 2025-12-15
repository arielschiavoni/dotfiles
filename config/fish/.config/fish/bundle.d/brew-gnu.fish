# Homebrew GNU tools and compiler overrides
# This file adds Homebrew-installed GNU utilities and GCC to PATH with higher
# priority than macOS system utilities. Only applied on macOS.
#
# WHY THIS IS NEEDED:
# - macOS ships with BSD versions of common utilities (sed, ls, etc.) that have
#   different behavior than GNU versions used on Linux
# - macOS provides Apple Clang disguised as 'gcc', not real GCC
# - Homebrew installs GNU tools with prefixes (gsed, gls) or version suffixes
#   (gcc-15) to avoid conflicts with macOS system binaries
# - The 'libexec/gnubin' directories contain unprefixed versions of GNU tools
# - For GCC, we use ~/.local/bin symlinks since Homebrew only provides versioned
#   binaries (gcc-15), but many build tools expect 'gcc' to be in PATH
#
# This ensures consistent behavior across macOS and Linux development environments.

if test (uname) = Darwin
    set -l brew_opt /opt/homebrew/opt

    # Helper function to add path if directory exists
    function _add_path_if_exists
        test -d $argv[1]; and fish_add_path --prepend --global $argv[1]
    end

    # User local binaries (highest priority)
    # Contains symlinks to versioned GCC (gcc -> gcc-15, g++ -> g++-15, etc.)
    # These must be created manually: ln -sf /opt/homebrew/bin/gcc-15 ~/.local/bin/gcc
    _add_path_if_exists ~/.local/bin

    # GNU coreutils (GNU versions of ls, cp, mv, etc.)
    # Adds unprefixed versions (e.g., 'ls' instead of 'gls')
    _add_path_if_exists $brew_opt/coreutils/libexec/gnubin

    # GNU sed (replaces BSD sed with GNU sed)
    # Allows using 'sed' instead of 'gsed'
    _add_path_if_exists $brew_opt/gnu-sed/libexec/gnubin

    # ncurses (newer version than macOS system ncurses)
    # Provides updated terminal utilities like 'clear', 'tput', etc.
    _add_path_if_exists $brew_opt/ncurses/bin

    # Python 3.11 (unprefixed python3 command)
    _add_path_if_exists $brew_opt/python@3.11/libexec/bin

    # OpenSSL 3.x (newer than macOS LibreSSL)
    _add_path_if_exists $brew_opt/openssl@3/bin

    # GnuPG 2.2 (newer version for better compatibility)
    _add_path_if_exists $brew_opt/gnupg@2.2/bin

    # GCC (real GCC, not Apple Clang)
    # Adds versioned GCC binaries (gcc-15, g++-15, etc.) to PATH
    _add_path_if_exists $brew_opt/gcc/bin

    # Clean up helper function
    functions -e _add_path_if_exists

    # Set default C compiler to GCC 15 (for build tools like make)
    # This ensures that when you run 'make' or other build systems,
    # they use real GCC instead of Apple Clang
    if test -x /opt/homebrew/bin/gcc-15
        set -gx CC /opt/homebrew/bin/gcc-15
    end
end
