#!/usr/bin/env bash
# Destroy the devbox VM.
#
# Everything in the VM is reproducible: this repo defines the VM, mise.toml
# defines the tools, and source code durability comes from `git push`.
# Still confirms first, because uncommitted work in ~/devbox is not.
set -euo pipefail

INSTANCE="${DEVBOX_INSTANCE:-devbox}"

limactl list --quiet 2>/dev/null | grep -qx "$INSTANCE" || {
  echo "No such instance: $INSTANCE"; exit 0
}

echo "About to permanently delete instance '$INSTANCE' and its disk image."
echo "Anything in ~/devbox that is not pushed to a git remote will be lost."
echo
read -r -p "Type the instance name to confirm: " CONFIRM
[ "$CONFIRM" = "$INSTANCE" ] || { echo "Aborted."; exit 1; }

limactl stop --force "$INSTANCE" 2>/dev/null || true
limactl delete --force "$INSTANCE"
echo "Deleted instance '$INSTANCE'."
echo
echo "Note: ~/share on the host is untouched."
echo "Recreate with: scripts/create.sh"
