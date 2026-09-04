#!/bin/bash
# devbox system bootstrap - runs as root on EVERY boot, and on demand via
# scripts/upgrade.sh.
#
# Idempotent: every step re-converges to the state declared here rather than
# recording that it has run once, so editing this script and re-running it is
# enough to bring an existing VM up to date.
set -euo pipefail

# Holds .system-ready only - the signal the lima.yaml readiness probe waits on.
# This is not an "already done" marker: nothing in this script skips work
# because of it, and it is rewritten unconditionally at the end of every run.
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
# apt - refresh, optional full upgrade, bootstrap packages
#
# Deliberately NOT behind a marker file. A marker pins the package list at the
# value it had on first boot, so adding a package below would never reach a VM
# that had already run once - which is exactly how `unzip` went missing before.
# apt-get install is idempotent and returns in well under a second when every
# package is already present, so the list simply re-converges on every run.
#
# DEVBOX_APT_UPGRADE gates `apt-get upgrade`, the one slow and genuinely risky
# step: it can take minutes and can pull a kernel that needs another reboot.
# Default off, so `limactl start` stays fast and predictable. It is an
# environment variable rather than a flag because Lima invokes provision
# scripts with no arguments; scripts/upgrade.sh sets it explicitly.
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive

# Non-fatal on purpose. Under `set -e` an offline boot would abort here, before
# the .system-ready touch at the end of this script, and `limactl start` would
# then block on its readiness probe for 300s before failing. Package lists a
# few days stale are a far smaller problem than a VM that will not start.
log "refreshing apt package lists"
apt-get update || log "WARN: apt-get update failed - continuing with cached lists"

if [ "${DEVBOX_APT_UPGRADE:-0}" = 1 ]; then
  log "upgrading installed apt packages"
  apt-get upgrade -y
else
  log "skipping apt upgrade (set DEVBOX_APT_UPGRADE=1 to enable)"
fi

log "installing bootstrap packages"
apt-get install -y --no-install-recommends \
  curl \
  git \
  ca-certificates \
  build-essential \
  libssl-dev \
  stow \
  unzip

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
