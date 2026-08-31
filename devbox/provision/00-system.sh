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
    libssl-dev \
    stow \
    unzip
  touch "${MARKER_DIR}/.apt-done"
else
  log "apt bootstrap already done"
fi

# ---------------------------------------------------------------------------
# locale - Debian genericcloud ships only C, C.UTF-8 and POSIX.
#
# glibc locales must be COMPILED from their source definition before
# setlocale() can use them. Debian ships every ingredient and bakes none:
# /usr/share/i18n/locales/en_US exists, /etc/locale.gen lists en_US.UTF-8 but
# leaves it commented out, so only C.UTF-8 (which needs no generation) is
# available. Ubuntu's cloud images pre-generate en_US.UTF-8, which is why this
# was not needed before the ubuntu-26.04 -> debian-13 switch.
#
# It matters because the macOS host exports LC_ALL/LANG=en_US.UTF-8
# (config/fish/.config/fish/conf.d/10-env.fish) and ssh forwards them —
# SendEnv on the host, AcceptEnv on the guest — so every login printed:
#   bash: warning: setlocale: LC_ALL: cannot change locale (en_US.UTF-8)
#
# update-locale additionally sets the system default, so sessions that do NOT
# arrive over ssh (limactl shell, cron, systemd units) get the same locale
# rather than depending on what the client happened to forward.
#
# The outer guard keeps this a logged no-op on any distro without glibc's
# locale tooling (e.g. musl/Alpine) instead of aborting provisioning.
# ---------------------------------------------------------------------------
if command -v locale-gen >/dev/null 2>&1 && [ -f /etc/locale.gen ]; then
  if ! locale -a 2>/dev/null | grep -qix "en_US.utf8"; then
    log "generating en_US.UTF-8 locale"
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    update-locale LANG=en_US.UTF-8
  else
    log "en_US.UTF-8 locale already generated"
  fi
else
  log "no locale-gen tooling found - skipping locale generation"
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
