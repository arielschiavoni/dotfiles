#!/usr/bin/env bash
# Emit an ~/.ssh/config block for the devbox VM.
#
# The SSH port is fixed in lima.yaml (ssh.localPort: 60022) so this block
# remains valid across destroy + create cycles. Only re-run this script if
# you've never added it to ~/.ssh/config.
set -euo pipefail

INSTANCE="devbox"

if ! limactl list --quiet 2>/dev/null | grep -qx "$INSTANCE"; then
  echo "# NOTE: instance '$INSTANCE' is not running - skipping"
  exit 0
fi

PORT=$(limactl list "$INSTANCE" --format '{{.SSHLocalPort}}' 2>/dev/null)

if [ -z "$PORT" ] || [ "$PORT" = "0" ]; then
  echo "# NOTE: could not read SSH port for '$INSTANCE' - is it running?" >&2
  exit 1
fi

cat << EOF
# ---8<--- add to ~/.ssh/config ---8<---
Host devbox
    HostName 127.0.0.1
    Port ${PORT}
    User devbox
    IdentityFile ${HOME}/.lima/_config/user
    IdentitiesOnly yes
    # Local VM: host keys are regenerated whenever the instance is rebuilt.
    NoHostAuthenticationForLocalhost yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    # Use xterm-256color instead of xterm-ghostty — the Ghostty terminfo entry
    # does not exist on Ubuntu and would cause "missing or unsuitable terminal".
    SetEnv TERM=xterm-256color
    # Keep long tmux/fish sessions alive.
    ServerAliveInterval 30
    ServerAliveCountMax 6
    # Reverse tunnel for the host bridge: the guest's \`xdg-open\` (links) and
    # \`xclip\` (image paste) write here and reach the \`devbox-bridge\` daemon on
    # the Mac. Loopback on both ends.
    # The port is also PORT in that crate's src/lib.rs; keep them in step.
    #
    # A second concurrent \`ssh devbox\` warns "remote port forwarding failed"
    # because the first session owns the port. Harmless - that tunnel serves
    # both. Do NOT add ExitOnForwardFailure, or the second session would refuse
    # to connect.
    RemoteForward 127.0.0.1:17325 127.0.0.1:17325
    # Attach to a persistent guest-side tmux session on connect. Bare \`tmux
    # attach\` first so the most-recently-used session wins - that makes the
    # alt-backtick hop (see tmux.conf / devbox_hop) symmetric, returning you to
    # remote session you left rather than always to 'base'.
    #
    # RemoteCommand makes \`ssh devbox <cmd>\` fail with "Cannot execute
    # command-line and remote command." For scripted use, bypass it:
    #     ssh -o RemoteCommand=none -T devbox tmux list-sessions
    RequestTTY yes
    RemoteCommand tmux attach || tmux new-session -A -s base
# ---8<--- end ---8<---
EOF
