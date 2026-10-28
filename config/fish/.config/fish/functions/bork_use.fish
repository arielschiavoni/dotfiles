function bork_use -d 'Select the bork CLI build pi runs: a BORK worktree or stable bork'
    # Usage: bork_use [stable|<dir>]
    #   no argument: fzf over the current dir's worktree, stable and every
    #   built BORK worktree under ~/repos (tmux: prefix o b)
    #
    # pi's mcp.json runs ~/.bork/bin/bork, a symlink to either the stable bork
    # (mise's npm:@asg-song/bork-cli) or a worktree's packages/cli/dist/cli.js,
    # so every repo gets the selected build. ~/.bork: pi-safe mounts it
    # read-only for bork, and a symlink in a mounted dir stays a symlink.
    # Build the worktree first (pnpm --filter @asg-song/bork-cli build), then
    # restart pi or /reload.
    #
    # Runs in a `tmux popup -EE`, so a cancel returns 0 (popup closes) and only
    # real errors return 1 (popup stays open with the message).
    set -l link ~/.bork/bin/bork
    # mise's `latest` symlink, so upgrades need no relink; the pnpm shim
    # resolves $0 through symlinks to find its package
    set -l stable ~/.local/share/mise/installs/npm-asg-song-bork-cli/latest/bin/bork
    set -l target
    switch "$argv[1]"
        case ''
            set -l current (readlink $link)
            # the current dir's worktree first, then org/repo and
            # org/repo/<worktree> clones (git_clone_bare layout)
            # `set`: a glob without matches is no error there
            set -l pkgs ~/repos/*/*/packages/cli/package.json ~/repos/*/*/*/packages/cli/package.json
            set -l roots
            for root in (git rev-parse --show-toplevel 2>/dev/null) \
                (string replace /packages/cli/package.json '' -- $pkgs)
                contains -- $root $roots; and continue
                test -x $root/packages/cli/dist/cli.js; or continue
                string match -q '*"name": "@asg-song/bork-cli"*' <$root/packages/cli/package.json
                and set -a roots $root
            end

            set -l lines
            for root in $roots
                set -l js $root/packages/cli/dist/cli.js
                set -l age (path mtime --relative $js)
                if test $age -lt 3600
                    set age (math --scale=0 $age / 60)m
                else if test $age -lt 86400
                    set age (math --scale=0 $age / 3600)h
                else
                    set age (math --scale=0 $age / 86400)d
                end
                set -a lines (string replace -r "^$HOME" '~' -- $root)"  built $age ago"\t$js
            end
            # stable after the current dir's build, else first
            set -l ver (path basename (path resolve (path dirname (path dirname $stable))))
            set -l stable_line "stable  mise npm:@asg-song/bork-cli $ver"\t$stable
            if test -n "$roots"; and test "$roots[1]" = (git rev-parse --show-toplevel 2>/dev/null)
                set lines $lines[1] $stable_line $lines[2..]
            else
                set -p lines $stable_line
            end

            # the current target's line: green, tagged [current]
            for i in (seq (count $lines))
                set -l parts (string split \t -- $lines[$i])
                test "$parts[2]" = "$current"; or continue
                set lines[$i] (set_color green)"$parts[1]  [current]"(set_color normal)\t$parts[2]
            end

            set -l pick (printf '%s\n' $lines | fzf --ansi --delimiter=\t --with-nth=1 --no-sort \
                --prompt='bork> ')
            or return 0 # fzf cancelled
            set target (string split -f2 \t -- $pick)
        case stable
            set target $stable
        case '*'
            set -l root (git -C $argv[1] rev-parse --show-toplevel); or return 1
            set target $root/packages/cli/dist/cli.js
    end
    if not test -x "$target"
        echo "bork_use: $target missing or not executable" >&2
        return 1
    end
    mkdir -p (path dirname $link); and ln -sfn "$target" $link; or return 1
    echo "bork -> $target"
    # the popup closes on success; tmux shows the result in the status line
    set -q TMUX; and tmux display-message "bork -> $target"
    return 0
end
