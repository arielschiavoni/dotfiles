function agent_mention -d 'Pick files with fzf and type them as @mentions into a tmux pane'
    # Usage: agent_mention share|repos <pane-id>
    #   share  ~/share/screenshots and ~/share/agent, newest first: files handed
    #          over from the Mac (the stand-in for clipboard image paste)
    #   repos  ~/repos, gitignore-aware (~30k files, no node_modules or .env):
    #          a file from another repo. Kept apart so screenshots are not
    #          buried under repo files.
    # Both are read-only inside pi-safe, so every pick is readable there too.
    # Tab selects several.
    #
    # Runs in a `tmux popup -EE`, so a cancel returns 0 (popup closes) and only
    # real errors return 1 (popup stays open with the message).
    set -l mode $argv[1]
    set -l pane $argv[2]
    if not contains -- "$mode" share repos; or test -z "$pane"
        echo "usage: agent_mention share|repos <pane-id>" >&2
        return 1
    end

    # The ~ form in mentions: shorter, and the same path in and out of pi-safe
    set -l base ~/$mode
    set -l display "~/$mode"
    cd $base; or return 1

    set -l list
    if test $mode = share
        set -l dirs
        for d in screenshots agent
            test -d $d; and set -a dirs $d
        end
        if test (count $dirs) -eq 0
            echo "Error: neither ~/share/screenshots nor ~/share/agent exists." >&2
            return 1
        end
        set list fd --type f . $dirs --exec-batch ls -t
    else
        # .bare: git dir of the bare-clone + worktrees layout (repo/.bare, repo/<branch>)
        set list fd --type f --hidden --exclude .git --exclude .bare
    end

    set -l picks ($list | fzf --multi --scheme=path --prompt="$display/ ")
    or return 0 # fzf cancelled

    set -l mentions
    for p in $picks
        set -l path "$display/"(string replace -r '^\./' '' -- $p)
        # pi's @ syntax for paths with spaces (e.g. macOS "Screenshot … .png")
        if string match -qr '\s' -- $path
            set -a mentions "@\"$path\""
        else
            set -a mentions "@$path"
        end
    end

    # -l: literal text, not key names; the trailing space ends the mention
    tmux send-keys -t $pane -l (string join ' ' $mentions)' '
end
