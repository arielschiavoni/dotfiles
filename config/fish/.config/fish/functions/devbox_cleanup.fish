function devbox_cleanup -d "Free disk space in the devbox: caches, old tool versions, build output"
    argparse h/help n/dry-run node-modules docker -- $argv; or return 2
    if set -q _flag_help; or set -q argv[1]
        echo "usage: devbox_cleanup [-n|--dry-run] [--node-modules] [--docker]"
        echo
        echo "Clears mise, pnpm, uv, npm, go and apt caches, unused mise tool"
        echo "versions, the dotfiles Rust build output and old journal logs, then"
        echo "trims the disk so the Mac reclaims the space. All of it is"
        echo "downloaded or rebuilt again on demand."
        echo
        echo "  -n, --dry-run   print the steps without running them"
        echo "  --node-modules  also delete every node_modules under ~/repos,"
        echo "                  except in the dotfiles repo"
        echo "                  (projects need 'pnpm install' again)"
        echo "  --docker        also remove unused images, containers, build cache"
        echo "                  AND volumes (database data in volumes is lost)"
        set -q _flag_help; and return 0
        return 2
    end

    if test (uname) != Linux
        echo "devbox_cleanup: runs inside the devbox VM" >&2
        return 2
    end

    set -l dry 0
    set -q _flag_dry_run; and set dry 1
    set -l failed
    set -l used_before (df -B1 --output=used / | tail -1)

    # Before `pnpm store prune`: the store keeps every package a node_modules
    # still links to. The dotfiles repo is skipped: its node_modules hold the
    # pi packages and opencode plugins, which nothing reinstalls on its own.
    if set -q _flag_node_modules
        set -l dirs (fd -H -I -t d --prune -E /arielschiavoni/dotfiles \
            '^node_modules$' ~/repos)
        echo "==> node_modules: "(count $dirs)" directories"
        if test $dry -eq 1
            set -q dirs[1]; and du -shc $dirs | sed 's/^/    /'
        else if set -q dirs[1]
            rm -rf $dirs; or set -a failed node_modules
        end
    end

    set -l steps \
        "mise prune --yes" \
        "mise cache clear" \
        "pnpm store prune" \
        "rm -rf $HOME/.cache/pnpm $HOME/.local/share/pnpm/package-manager-store" \
        "uv cache clean" \
        "npm cache clean --force" \
        "go clean -cache -modcache" \
        "cargo clean --manifest-path $HOME/repos/arielschiavoni/dotfiles/tools/Cargo.toml"
    set -q _flag_docker; and set -a steps "docker system prune -a --volumes --force"
    # fstrim last: it hands every block freed above back to the sparse image.
    set -a steps \
        "sudo apt-get clean" \
        "sudo journalctl --vacuum-time=7d" \
        "sudo fstrim -av"

    for step in $steps
        set -l cmd (string split ' ' -- $step)
        set -l bin $cmd[1]
        test $bin = sudo; and set bin $cmd[2]
        if not type -q $bin
            echo "==> $step (skipped: $bin not installed)"
            continue
        end
        echo "==> $step"
        test $dry -eq 1; and continue
        $cmd; or set -a failed $cmd[1..2]
    end

    if test $dry -eq 0
        set -l freed (math $used_before - (df -B1 --output=used / | tail -1))
        test $freed -lt 0; and set freed 0
        echo
        echo "freed "(numfmt --to=iec $freed)" in the guest"
        echo "on the Mac: du -h ~/.lima/devbox/disk"
    end

    if set -q failed[1]
        echo "devbox_cleanup: failed: $failed" >&2
        return 2
    end
end
