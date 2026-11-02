function skill_link -d 'Link or unlink audi-agentic-capabilities skills in a project'
    # Usage: skill_link [<project-dir>]          fzf popup, Enter toggles a link
    #        skill_link list|toggle|clean <project-dir> [<skill-dir>]  (internal)
    #
    # Links <project>/.agents/skills/<name> -> <worktree>/capabilities/<name>
    # for every worktree of the capabilities repo except main (tmux: prefix o l). pi reads
    # project .agents/skills/ from the cwd up to the git root, so the link is
    # live: edit the skill in the worktree, /reload pi. Only links into the
    # capabilities repo are ever touched.
    #
    # Runs in a `tmux popup -EE`, so a cancel returns 0 (popup closes) and only
    # real errors return 1 (popup stays open with the message).
    set -l repo ~/repos/ASG-SONG/315783_STO_0100-audi-agentic-capabilities
    set -l action list
    set -l args $argv
    if contains -- "$argv[1]" list toggle clean
        set action $argv[1]
        set args $argv[2..]
    else
        set action pick
    end

    set -l dir $args[1]
    test -n "$dir"; or set dir $PWD
    set -l root (git -C $dir rev-parse --show-toplevel 2>/dev/null); or set root $dir
    set -l dest $root/.agents/skills

    switch $action
        case pick
            test -d $repo; or begin
                echo "skill_link: $repo missing" >&2
                return 1
            end
            # fzf runs its bindings through $SHELL
            set -lx SHELL (command -s fish)
            skill_link list $root | fzf --ansi --delimiter=\t --with-nth=1 --no-sort \
                --track --id-nth=2 \
                --header="$root  (enter: link/unlink)" --prompt='skill> ' \
                --bind "enter:execute-silent(skill_link toggle $root {2})+reload(skill_link list $root)"
            return 0 # fzf cancelled or closed
        case list
            for skill in $repo/*/capabilities/*/SKILL.md
                # main is what gets installed globally
                string match -q "$repo/main/*" -- $skill; and continue
                set -l src (path dirname $skill)
                set -l name (path basename $src)
                set -l wt (path basename (path dirname (path dirname $src)))
                set -l line (printf '%-34s %s' $name "[$wt]")
                if test -L $dest/$name; and test (readlink $dest/$name) = $src
                    set line (set_color green)"$line  [linked]"(set_color normal)
                else if test -L $dest/$name; and string match -q "$repo/*" (readlink $dest/$name)
                    set line (set_color yellow)"$line  [other: "(path basename (path dirname (path dirname (readlink $dest/$name))))"]"(set_color normal)
                end
                printf '%s\t%s\n' $line $src
            end
        case toggle
            set -l src $args[2]
            string match -q "$repo/*/capabilities/*" -- $src; or return 1
            set -l link $dest/(path basename $src)
            if test -L $link
                string match -q "$repo/*" (readlink $link); or return 1
                set -l same (test (readlink $link) = $src; and echo 1)
                rm $link
                test -n "$same"; and return 0
            else if test -e $link
                echo "skill_link: $link exists and is not a link" >&2
                return 1
            end
            mkdir -p $dest; and ln -s $src $link
            # keep the links out of the project's git status
            set -l excl (git -C $root rev-parse --git-path info/exclude 2>/dev/null)
            if test -n "$excl"; and not grep -qxF /.agents/skills/ $excl 2>/dev/null
                mkdir -p (path dirname $excl); and echo /.agents/skills/ >>$excl
            end
        case clean
            for link in $dest/*
                test -L $link; or continue
                string match -q "$repo/*" (readlink $link); and rm $link
            end
    end
end
