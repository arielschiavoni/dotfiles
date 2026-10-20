function mac_sync -d "Back up or restore important home directories over SSH"
    argparse h/help n/dry-run delete 'host=' 'dest=' -- $argv; or return 2

    set -l mode $argv[1]
    set -l dirs $argv[2..]
    if set -q _flag_help; or not contains -- "$mode" backup restore
        echo "usage: mac_sync backup|restore [options] [dir...]"
        echo
        echo "Copies directories under \$HOME to and from <host>:<dest>, keeping"
        echo "their path relative to \$HOME (~/.ssh <-> <dest>/.ssh)."
        echo
        echo "  --host HOST   SSH destination (default: arch)"
        echo "  --dest PATH   directory on HOST (default: /home/ariel/Mac)"
        echo "  -n, --dry-run show what would be transferred"
        echo "  --delete      also remove files missing on the sending side"
        echo
        echo "Default dirs: .local share Documents .ssh .aws Downloads .gnupg"
        set -q _flag_help; and return 0
        return 2
    end

    set -l host arch
    set -q _flag_host; and set host $_flag_host
    set -l dest /home/ariel/Mac
    set -q _flag_dest; and set dest (string trim -r -c / -- $_flag_dest)
    set -q dirs[1]; or set dirs .local share Documents .ssh .aws Downloads .gnupg

    # macOS ships openrsync, which lacks --info and --mkpath.
    if not command rsync --version 2>/dev/null | string match -qr 'rsync\s+version 3\.'
        echo "mac_sync: needs rsync 3.x (brew install rsync)" >&2
        return 2
    end

    # -R with a /./ marker recreates the path from $HOME onwards on the other
    # side. No compression: the link is a local network. Sockets and gpg-agent
    # lock files are runtime state, not data.
    set -l opts -aHRS --no-D --partial --human-readable --info=stats1,progress2 \
        --exclude=.DS_Store --exclude='/.gnupg/**.lock'
    set -q _flag_dry_run; and set -a opts --dry-run --itemize-changes
    set -q _flag_delete; and set -a opts --delete

    set -l failed
    for dir in $dirs
        set dir (string trim -r -c / -- $dir)
        echo "==> $mode ~/$dir"
        if test $mode = backup
            if not test -e ~/$dir
                echo "    skipped: ~/$dir does not exist"
                continue
            end
            command rsync $opts --mkpath ~/./$dir $host:$dest/
        else
            command rsync $opts $host:$dest/./$dir ~/
        end
        set -l code $status
        # 24: files vanished during the transfer, normal for a live home dir.
        if test $code -ne 0 -a $code -ne 24
            echo "    FAILED: rsync exit $code" >&2
            set -a failed $dir
        end
    end

    if test $mode = restore; and not set -q _flag_dry_run
        # ssh and gpg refuse keys in directories others can read.
        for dir in .ssh .gnupg
            test -d ~/$dir; and chmod 700 ~/$dir
        end
        # A running agent keeps its old view of the keyring.
        contains -- .gnupg $dirs; and type -q gpgconf; and gpgconf --kill gpg-agent
    end

    if set -q failed[1]
        echo "mac_sync: failed: $failed" >&2
        return 2
    end
end
