function find_password -d "Fuzzy searches a password in all gopass stores and copies it to the clipboard after selection"
    set selection (gopass ls --flat | fzf --preview "gopass show {}" --preview-window=hidden --bind "ctrl-/:toggle-preview")

    if test $selection
        if test (uname) = Darwin
            gopass show $selection | pbcopy
        else if type -q wl-copy
            gopass show $selection | wl-copy
        else if set -q TMUX
            # Headless devbox: no compositor, so no wl-copy. `load-buffer` reads
            # the password from stdin (`-`) into a tmux buffer; `-w` also emits
            # OSC 52 to the client terminal, which ssh carries to the Mac.
            # Printing OSC 52 here directly would not work - set-clipboard is
            # `external`, so tmux drops sequences originating inside a pane.
            gopass show $selection | tmux load-buffer -w -
        else
            echo "find_password: no clipboard available (no wl-copy, not in tmux)" >&2
            return 1
        end
    end
end
