#!/usr/bin/env bash
# Emit an ~/.ssh/config block for the devbox VM.
#
# Lima reassigns SSHLocalPort when an instance is recreated.
# Re-run this script after any destroy + create cycle and update ~/.ssh/config.
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
    # Keep long tmux/fish sessions alive.
    ServerAliveInterval 30
    ServerAliveCountMax 6
    # Attach to a persistent guest-side tmux session on connect.
    RequestTTY yes
    RemoteCommand tmux new-session -A -s main
# ---8<--- end ---8<---

# Note: port changes on every destroy+create. Re-run this script to refresh.
EOF
