#!/usr/bin/env bash
# Create the devbox VM.
# - Streams provisioning output via --progress.
# Idempotent: refuses to clobber an existing instance.
set -euo pipefail

DEVBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$DEVBOX_DIR/.." && pwd)"
INSTANCE="devbox"
BRIDGE_PORT=17325

command -v limactl >/dev/null 2>&1 || {
  echo "limactl not found. Install with: brew install lima" >&2
  exit 1
}

# Ensure the host-side share directory exists before Lima tries to mount it
mkdir -p "$HOME/share"

# ---------------------------------------------------------------------------
# Host-side bridge daemon (URLs + clipboard)
#
# Deliberately ABOVE the "instance already exists" early exit: this is host
# infrastructure, independent of the VM lifecycle, so an existing VM must still
# get it - which also makes this script a "repair my host side" entry point.
#
# It cannot live in Lima provisioning: those scripts run INSIDE the guest, which
# has no access to launchctl out here.
#
# Non-fatal: a missing cargo must not stop the VM from being created.
# ---------------------------------------------------------------------------
echo "==> Host-side bridge daemon (tools/crates/devbox-bridge)"
bridge_ok=0
if command -v cargo >/dev/null 2>&1; then
  # --force: cargo tracks installs as "name version (source)" with no content
  # hash, so an edit under a static 0.1.0 is silently skipped.
  if cargo install --path "$REPO_DIR/tools/crates/devbox-bridge" \
    --bin devbox-bridge --locked --force --quiet \
    && "$HOME/.cargo/bin/devbox-bridge" --install; then
    bridge_ok=1
  else
    echo "    WARN: could not build or load the bridge daemon." >&2
    echo "          Links and image paste from the VM will not work." >&2
  fi
else
  echo "    WARN: cargo not found - skipping. Install Rust, then re-run." >&2
fi

# Forgetting the tunnel produces a bare "connection refused" inside lazygit.
# Warn rather than edit ~/.ssh/config: it holds unrelated work configs, and
# ssh-config.sh already chose to emit text for review rather than edit.
if ! grep -qs "RemoteForward 127.0.0.1:${BRIDGE_PORT}" "$HOME/.ssh/config"; then
  # Flat, not a drawn box: the absolute path below breaks out of any box that
  # fits in 80 columns.
  echo
  echo "    !! ACTION REQUIRED ------------------------------------------------"
  echo "    Your ~/.ssh/config devbox block is missing the reverse tunnel, so"
  echo "    links and image paste from inside the VM will fail. Add this to it:"
  echo
  echo "        RemoteForward 127.0.0.1:${BRIDGE_PORT} 127.0.0.1:${BRIDGE_PORT}"
  echo
  echo "    or regenerate the whole block with:"
  echo "        $DEVBOX_DIR/scripts/ssh-config.sh"
  echo "    ------------------------------------------------------------------"
  echo
elif [ "$bridge_ok" -eq 1 ]; then
  echo "    ok: daemon loaded and ~/.ssh/config has the reverse tunnel"
fi

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
echo "    Bridge to the Mac: devbox-bridge --status  (then, in the VM: xdg-open https://example.com)"
