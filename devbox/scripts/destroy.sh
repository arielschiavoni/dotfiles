#!/usr/bin/env bash
# Destroy the devbox VM.
#
# Everything in the VM is reproducible: this repo defines the VM, mise.toml
# defines the tools, and source code durability comes from `git push`.
set -euo pipefail

INSTANCE="${DEVBOX_INSTANCE:-devbox}"

limactl list 2>/dev/null | grep -q "^$INSTANCE " || {
  echo "No such instance: $INSTANCE"; exit 0
}

echo "Destroying instance '$INSTANCE' and its disk image."
echo "Anything in ~/devbox that is not pushed to a git remote will be lost."
echo

limactl stop --force "$INSTANCE" 2>/dev/null || true
limactl delete --force "$INSTANCE"
echo "Deleted instance '$INSTANCE'."
echo
echo "Note: ~/share on the host is untouched."
echo "Recreate with: scripts/create.sh"
