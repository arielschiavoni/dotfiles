#!/bin/bash
# devbox system bootstrap - runs as root on EVERY boot.
# Idempotent: each step checks its own marker before running.
set -euo pipefail

MARKER_DIR=/var/lib/devbox
mkdir -p "$MARKER_DIR"

log() { echo "[devbox/system] $*"; }

# ---------------------------------------------------------------------------
# fstrim - return freed guest blocks to the sparse APFS host image
# ---------------------------------------------------------------------------
if systemctl list-unit-files fstrim.timer >/dev/null 2>&1; then
  systemctl enable --now fstrim.timer >/dev/null 2>&1 || log "WARN fstrim.timer"
fi

# ---------------------------------------------------------------------------
# apt upgrade + bootstrap packages
# ---------------------------------------------------------------------------
# if [ ! -f "${MARKER_DIR}/.apt-done" ]; then
#   log "upgrading apt packages and installing bootstrap deps"
#   export DEBIAN_FRONTEND=noninteractive
#   apt-get update
#   apt-get upgrade -y
#   apt-get install -y --no-install-recommends \
#     curl \
#     git \
#     ca-certificates \
#     build-essential \
#     libssl-dev
#   touch "${MARKER_DIR}/.apt-done"
# else
#   log "apt bootstrap already done"
# fi

# ---------------------------------------------------------------------------
# mise - install to /usr/local/bin so all users can run it
# ---------------------------------------------------------------------------
if [ ! -x /usr/local/bin/mise ]; then
  log "installing mise"
  curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
else
  log "mise already installed ($(mise --version 2>/dev/null || echo unknown))"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
touch "${MARKER_DIR}/.system-ready"
log "system provisioning complete"
