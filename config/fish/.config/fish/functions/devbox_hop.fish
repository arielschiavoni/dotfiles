function devbox_hop -d "Attach to the devbox tmux server, then return to the local one"
    # Run by tmux's `detach-client -E` binding (see tmux.conf). That flag
    # overrides what a client does on detach: instead of exiting it execs this,
    # so the local terminal *becomes* the ssh session. The remote tmux is
    # therefore not nested inside the local one and C-a always addresses
    # whichever server is on screen.
    #
    # A tmux client can only ever be attached to one server, so this is a swap,
    # not a switch: detach here, attach there, and back.
    ssh devbox
    set -l rc $status

    # Detaching on the far side ends the ssh RemoteCommand, so ssh returns 0 and
    # we fall straight through to the re-attach. Any other status means we never
    # got there (VM down, provisioning left fish off PATH) - hold the error on
    # screen instead of snapping back and hiding it.
    if test $rc -ne 0
        echo "devbox_hop: ssh exited $rc - check 'limactl list'" >&2
        read -P "press enter to return to the local session "
    end

    # No target: tmux picks the most-recently-used session, which is the one we
    # detached from. The fallback covers a local server with no sessions left.
    tmux attach; or tmux new-session -s base
end
