#!/usr/bin/env bash
# Create the devbox VM.
# - Streams provisioning output via --progress.
# Idempotent: refuses to clobber an existing instance.
set -euo pipefail

DEVBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$DEVBOX_DIR/.." && pwd)"
INSTANCE="devbox"
OPEN_URL_PORT=17325

command -v limactl >/dev/null 2>&1 || {
  echo "limactl not found. Install with: brew install lima" >&2
  exit 1
}

# Ensure the host-side share directory exists before Lima tries to mount it
mkdir -p "$HOME/share"

# ---------------------------------------------------------------------------
# Host-side URL opener
#
# Deliberately ABOVE the "instance already exists" early exit below: this is
# host infrastructure, independent of the VM's lifecycle, so an already-created
# VM must still get it. That also makes this script a valid "repair my host
# side" entry point after editing the daemon.
#
# This cannot live in Lima provisioning, which is the intuitive place for it.
# Provision scripts run INSIDE the guest (lima.yaml), which has no access to
# launchctl out here - and granting the guest that access, in one narrow
# direction, is exactly what this daemon is for.
#
# Non-fatal: a missing cargo must not stop the VM from being created.
# ---------------------------------------------------------------------------
echo "==> Host-side URL opener (tools/crates/devbox-open-url)"
open_url_ok=0
if command -v cargo >/dev/null 2>&1; then
  # --force is required: cargo tracks installs in ~/.cargo/.crates2.json as
  # "name version (source)" with no content hash, so an edit under a static
  # 0.1.0 is silently skipped and you keep running the old binary.
  if cargo install --path "$REPO_DIR/tools/crates/devbox-open-url" \
    --bin devbox-open-url --locked --force --quiet \
    && "$HOME/.cargo/bin/devbox-open-url" --install; then
    open_url_ok=1
  else
    echo "    WARN: could not build or load the URL opener." >&2
    echo "          Links from the VM will not open until this is fixed." >&2
  fi
else
  echo "    WARN: cargo not found - skipping. Install Rust, then re-run." >&2
fi

# The guest half is useless without the reverse tunnel, and forgetting it
# produces a bare "connection refused" inside lazygit. Warn loudly rather than
# editing ~/.ssh/config: that file holds unrelated work configs, and
# ssh-config.sh already made the decision to emit text for review, not to edit.
if ! grep -qs "RemoteForward 127.0.0.1:${OPEN_URL_PORT}" "$HOME/.ssh/config"; then
  # Flat layout on purpose: a drawn box needs the padding to match the content
  # width, and the absolute path below is long enough to break out of any box
  # that fits in 80 columns.
  echo
  echo "    !! ACTION REQUIRED ------------------------------------------------"
  echo "    Your ~/.ssh/config devbox block is missing the reverse tunnel, so"
  echo "    opening links from inside the VM will fail. Add this to it:"
  echo
  echo "        RemoteForward 127.0.0.1:${OPEN_URL_PORT} 127.0.0.1:${OPEN_URL_PORT}"
  echo
  echo "    or regenerate the whole block with:"
  echo "        $DEVBOX_DIR/scripts/ssh-config.sh"
  echo "    ------------------------------------------------------------------"
  echo
elif [ "$open_url_ok" -eq 1 ]; then
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
echo "    Open links on the Mac: devbox-open-url --status  (then, in the VM: xdg-open https://example.com)"
