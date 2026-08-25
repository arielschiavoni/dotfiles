#!/usr/bin/env bash
# Create the devbox VM.
# - Creates the devbox-transfer disk (10GiB) if it doesn't exist.
# - Streams provisioning output via --progress.
# Idempotent: refuses to clobber an existing instance.
set -euo pipefail

DEVBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANCE="devbox"

command -v limactl >/dev/null 2>&1 || {
  echo "limactl not found. Install with: brew install lima" >&2
  exit 1
}

# Ensure the host-side share directory exists before Lima tries to mount it
mkdir -p "$HOME/share"

# ---------------------------------------------------------------------------
# VM instance
# ---------------------------------------------------------------------------
if limactl list --quiet 2>/dev/null | grep -qx "$INSTANCE"; then
  echo "Instance '$INSTANCE' already exists."
  echo "  start:   limactl start $INSTANCE"
  echo "  shell:   limactl shell $INSTANCE"
  echo "  destroy: DEVBOX_INSTANCE=$INSTANCE $DEVBOX_DIR/scripts/destroy.sh"
  exit 0
fi

echo "==> Creating '$INSTANCE'"
echo "    First run downloads the Ubuntu 26.04 aarch64 cloud image."
echo "    Provisioning output will stream below."
echo
limactl start --name="$INSTANCE" --progress "$DEVBOX_DIR/lima.yaml"

echo
echo "==> devbox ready."
echo "    Update ~/.ssh/config:  $DEVBOX_DIR/scripts/ssh-config.sh"
echo "    SSH into VM:           ssh devbox"
echo "    Share files:           ~/share/ on the host is mounted at ~/share/ in the VM"
