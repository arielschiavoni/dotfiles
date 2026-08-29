#!/usr/bin/env bash
# Create the devbox VM.
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
  echo "    First run downloads the Debian 13 aarch64 cloud image."
echo "    Provisioning output will stream below."
echo

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN is not set." >&2
  echo "       mise install requires it to avoid GitHub API rate limits (60 req/hour)." >&2
  echo "       Set it with: export GITHUB_TOKEN=ghp_... and re-run." >&2
  exit 1
fi

limactl start --name="$INSTANCE" --progress --tty=false \
  --param "GithubToken=${GITHUB_TOKEN}" \
  "$DEVBOX_DIR/lima.yaml"

echo
echo "==> devbox ready."
echo "    Update ~/.ssh/config:  $DEVBOX_DIR/scripts/ssh-config.sh"
echo "    SSH into VM:           ssh devbox"
echo "    Share files:           ~/share/ on the host is mounted at ~/share/ in the VM"
