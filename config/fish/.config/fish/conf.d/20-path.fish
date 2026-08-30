# Every PATH entry, in one deliberate order. Highest priority first.
#
# WHY ONE FILE: `fish_add_path --prepend` puts its argument at the front, so when
# several conf.d snippets each prepend, the resulting precedence is the *reverse*
# of conf.d's alphabetical filename order. That is invisible, and renaming a file
# silently reorders PATH. Previously ~/.local/bin was documented as "highest
# priority" while actually landing 10th. One call makes precedence reviewable.
#
#   --path   operate on $PATH directly rather than on $fish_user_paths, which
#            fish splices in ahead of $PATH (this is why /opt/homebrew/bin used
#            to end up behind everything set here).
#   --move   reposition an entry that is already present, e.g. inherited from a
#            parent shell, rather than leaving it where it was.
#
# The universal $fish_user_paths is deliberately not used. It is machine-local
# state stored outside this repo, so entries added there never reach the devbox,
# and fish splices the whole list ahead of $PATH - which would put those entries
# in front of this ordering regardless of what is written below. The three
# entries it previously held are listed here instead, and the universal was
# erased. (~/.opencode/bin was dropped rather than carried over: that directory
# does not exist and opencode ships from /opt/homebrew/bin.)
#
# fish_add_path silently skips directories that do not exist, so no `test -d`
# guards are needed. The /opt/homebrew entries are simply absent on Linux.
#
# macOS ships BSD userland and Apple Clang disguised as gcc; the gnubin
# directories provide unprefixed GNU tools (`sed` rather than `gsed`) so that
# behaviour matches Linux.
fish_add_path --global --move --path \
    ~/.local/bin \
    /opt/homebrew/opt/coreutils/libexec/gnubin \
    /opt/homebrew/opt/gnu-sed/libexec/gnubin \
    /opt/homebrew/opt/ncurses/bin \
    /opt/homebrew/opt/python@3.14/libexec/bin \
    /opt/homebrew/opt/openssl@3/bin \
    /opt/homebrew/opt/gcc/bin \
    ~/.cargo/bin \
    $PNPM_HOME \
    ~/.amp/bin \
    ~/.lmstudio/bin \
    ~/.local/share/nvim/mason/bin \
    /opt/homebrew/opt/fzf/bin \
    /Applications/Ghostty.app/Contents/MacOS

# Real GCC rather than Apple Clang for make and other build tools.
# ~/.local/bin additionally holds manual symlinks (gcc -> gcc-16, g++ -> g++-16)
# because Homebrew only ships versioned binaries.
if test -x /opt/homebrew/bin/gcc-16
    set -gx CC /opt/homebrew/bin/gcc-16
end
