#!/usr/bin/env bash
# Snapshot the devbox disk image using APFS clonefile.
#
# The VM is STOPPED first, deliberately. Copying a running VM's disk image
# yields a crash-consistent image at best and a silently corrupt one at worst,
# because guest page cache and journal state are not on disk yet.
#
# `cp -c` uses clonefile(2): near-instant and copy-on-write, so a 100GiB
# sparse image costs almost nothing to snapshot. Lima's own docs recommend
# exactly this.
set -euo pipefail

INSTANCE="${DEVBOX_INSTANCE:-devbox}"
LIMA_DIR="${HOME}/.lima/${INSTANCE}"
SNAP_DIR="${DEVBOX_SNAPSHOT_DIR:-${HOME}/.lima-snapshots}"
KEEP="${DEVBOX_SNAPSHOT_KEEP:-3}"

[ -d "$LIMA_DIR" ] || { echo "No such instance: $INSTANCE" >&2; exit 1; }

WAS_RUNNING=0
if limactl list "$INSTANCE" --format '{{.Status}}' 2>/dev/null | grep -q Running; then
  WAS_RUNNING=1
  echo "==> stopping '$INSTANCE' for a consistent snapshot"
  limactl stop "$INSTANCE"
fi

STAMP=$(date +%Y%m%d-%H%M%S)
DEST="${SNAP_DIR}/${INSTANCE}-${STAMP}"
mkdir -p "$DEST"

echo "==> cloning disk image (APFS clonefile)"
shopt -s nullglob
for img in "$LIMA_DIR"/*.raw "$LIMA_DIR"/*.qcow2 "$LIMA_DIR"/efi-bl-*; do
  [ -e "$img" ] || continue
  cp -c "$img" "$DEST/" 2>/dev/null || cp "$img" "$DEST/"
  echo "    $(basename "$img")"
done
for meta in lima.yaml cidata.iso; do
  [ -e "$LIMA_DIR/$meta" ] && cp -c "$LIMA_DIR/$meta" "$DEST/" 2>/dev/null || true
done

echo "==> snapshot at $DEST"
du -sh "$DEST" | awk '{print "    actual allocation: "$1}'

# Prune old snapshots
mapfile -t SNAPS < <(find "$SNAP_DIR" -maxdepth 1 -type d -name "${INSTANCE}-*" | sort -r)
if [ "${#SNAPS[@]}" -gt "$KEEP" ]; then
  echo "==> pruning to $KEEP generations"
  for old in "${SNAPS[@]:$KEEP}"; do
    echo "    removing $(basename "$old")"
    rm -rf "$old"
  done
fi

if [ "$WAS_RUNNING" -eq 1 ]; then
  echo "==> restarting '$INSTANCE'"
  limactl start "$INSTANCE"
fi

echo
echo "Restore: stop the instance, then copy the images back into $LIMA_DIR"
