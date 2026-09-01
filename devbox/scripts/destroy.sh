#!/usr/bin/env bash
# Destroy the devbox VM.
#
# Everything in the VM is reproducible: this repo defines the VM, mise.toml
# defines the tools, and source code durability comes from `git push`.
#
# This is a deliberate choice over a persistent data volume: the VM stays
# genuinely disposable, at the cost of redoing the gopass/GPG setup on create.
# Use scripts/snapshot.sh if you want a restorable point-in-time copy instead.
set -euo pipefail

INSTANCE="${DEVBOX_INSTANCE:-devbox}"

limactl list 2>/dev/null | grep -q "^$INSTANCE " || {
  echo "No such instance: $INSTANCE"; exit 0
}

echo "Destroying instance '$INSTANCE' and its disk image."
echo
echo "There is no persistent data volume. The entire guest filesystem goes,"
echo "including /home/devbox.guest - so anything under ~/repos that is not"
echo "pushed to a git remote will be lost."
echo "The gopass/GPG setup will also have to be redone (see devbox/README.md)."
echo

limactl stop --force "$INSTANCE" 2>/dev/null || true
limactl delete --force "$INSTANCE"
echo "Deleted instance '$INSTANCE'."
echo
echo "Note: ~/share on the host is untouched."
echo "Recreate with: scripts/create.sh"
