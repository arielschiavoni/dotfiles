#!/bin/bash
# devbox system bootstrap - runs as root on EVERY boot.
# Idempotent: each step checks its own marker before running.
set -euo pipefail

MARKER_DIR=/var/lib/devbox
mkdir -p "$MARKER_DIR"

log() { echo "[devbox/system] $*"; }

# ---------------------------------------------------------------------------
# fstrim - return freed guest blocks to the sparse APFS host image
#
# The guest disk image is stored as a sparse file on the Mac.  Blocks are
# allocated on the host only as the guest writes to them, so the file starts
# small and grows organically.  The problem: when the guest deletes files,
# ext4 marks those blocks free internally but the hypervisor has no visibility
# into the guest filesystem — the sparse file on the host stays large.
#
# fstrim (TRIM/DISCARD) closes that gap.  It scans the mounted filesystem for
# free blocks and issues DISCARD commands to the virtual block device.  The
# hypervisor translates those into hole-punch calls on the sparse host file,
# physically reclaiming the unused space on the Mac.
#
# fstrim.timer runs the trim once a week (the systemd upstream default).
# That cadence is fine for normal use; run 'sudo fstrim -av' manually after
# deleting large build artefacts, node_modules, or Docker layers to reclaim
# space immediately without waiting for the timer.
# ---------------------------------------------------------------------------
if systemctl list-unit-files fstrim.timer >/dev/null 2>&1; then
  systemctl enable --now fstrim.timer >/dev/null 2>&1 || log "WARN fstrim.timer"
fi

# ---------------------------------------------------------------------------
# noatime - suppress access-time writes on every file read
#
# By default ext4 updates the atime timestamp whenever a file is read.
# In a filesystem-heavy workload (git, node_modules, compiler passes) this
# doubles I/O: one read + one metadata write per file touched.  Setting
# noatime eliminates that write completely.  It is safe for a dev VM because
# nothing here depends on atime semantics.
#
# Implementation: sed replaces the options field (column 4) of the / entry
# in /etc/fstab, inserting "noatime," before any existing options.  The
# change is picked up on the next boot; we also remount live so the current
# session benefits immediately.
# ---------------------------------------------------------------------------
if ! grep -qE '^[^#].*\s/\s.*noatime' /etc/fstab; then
  log "adding noatime to / in /etc/fstab"
  # Append noatime to the options column (field 4) of the root entry.
  sed -i -E 's|^([^#]\S+\s+/\s+\S+\s+)(\S+)(\s+.*)|\1noatime,\2\3|' /etc/fstab
  mount -o remount,noatime / || log "WARN: remount / noatime failed (will apply on next boot)"
else
  log "noatime already set on /"
fi

# ---------------------------------------------------------------------------
# sysctls - kernel tuning for developer workloads
#
# vm.vfs_cache_pressure=50
#   Default: 100.  Controls how aggressively the kernel reclaims memory used
#   for the VFS dentry/inode cache.  At 100 the kernel treats cache memory
#   the same as pagecache; at 50 it is half as eager to evict it.  Keeping
#   directory and inode entries in RAM means repeated traversals of large
#   trees (git, find, node_modules) hit memory instead of disk.  The cost is
#   slightly higher memory pressure under RAM contention, which is acceptable
#   on a 16 GiB VM dedicated to a single developer.
#
# fs.inotify.max_user_watches=524288
#   Default: 8192-131072 (distro-dependent).  Each inotify watch slot is
#   consumed by one watched file or directory.  Modern dev tools (Vite,
#   webpack, esbuild, Jest, language servers, editors) register watches
#   aggressively.  A large monorepo with node_modules can easily exhaust the
#   default limit, producing cryptic "ENOSPC" errors from inotify even when
#   disk space is plentiful.  524288 (512 K) is the recommended value for
#   developer machines and is consistent with the GitHub Codespaces default.
# ---------------------------------------------------------------------------
SYSCTL_CONF=/etc/sysctl.d/99-devbox.conf
if [ ! -f "$SYSCTL_CONF" ]; then
  log "writing $SYSCTL_CONF"
  cat > "$SYSCTL_CONF" << 'EOF'
# devbox kernel tuning - applied on every boot via sysctl.d(5)

# Keep dentry/inode caches in RAM twice as long as the default.
# Cuts repeated large-tree traversal cost (git, find, node_modules).
vm.vfs_cache_pressure = 50

# Allow up to 512 K inotify watches per user.
# Prevents ENOSPC errors from Vite, webpack, Jest, and language servers
# watching large repos with node_modules.
fs.inotify.max_user_watches = 524288
EOF
fi

# Apply immediately (idempotent - sysctl -p is safe to run on every boot).
sysctl --system >/dev/null 2>&1 || log "WARN: sysctl --system failed"

# ---------------------------------------------------------------------------
# apt upgrade + bootstrap packages
# ---------------------------------------------------------------------------
if [ ! -f "${MARKER_DIR}/.apt-done" ]; then
  log "upgrading apt packages and installing bootstrap deps"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get upgrade -y
  apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    build-essential \
    libssl-dev
  touch "${MARKER_DIR}/.apt-done"
else
  log "apt bootstrap already done"
fi

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
