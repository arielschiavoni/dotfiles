#!/usr/bin/env bash
# Verification checklist for the devbox VM.
#
# Every item here is something that was genuinely uncertain when this VM was
# designed, or something whose silent failure would negate the whole point.
set -uo pipefail

INSTANCE="${DEVBOX_INSTANCE:-devbox}"
g() { limactl shell "$INSTANCE" -- "$@" 2>/dev/null; }

pass=0; fail=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail+1)); }
info() { echo "  ..    $*"; }

echo "=== devbox verification: $INSTANCE ==="
echo

echo "[1] Instance running"
if limactl list "$INSTANCE" --format '{{.Status}}' 2>/dev/null | grep -q Running; then
  ok "instance is Running"
else
  bad "instance not Running"; exit 1
fi

echo
echo "[2] Internet + DNS out of the box"
g getent hosts archive.ubuntu.com >/dev/null && ok "DNS resolves" || bad "DNS failed"
g curl -fsS -o /dev/null --max-time 15 https://cloud-images.ubuntu.com/ \
  && ok "outbound HTTPS works" || bad "outbound HTTPS failed"

echo
echo "[3] Network interfaces / default route"
info "26.04 has a known first-boot NIC rename bug (LP #2136392) that Lima"
info "works around; vzNAT adds a second NIC, so confirm routing is sane."
g ip -brief addr show | sed 's/^/        /'
info "default route:"
g ip route show default | sed 's/^/        /'

echo
echo "[4] vzNAT guest IP (reachable from macOS Chrome)"
GUEST_IP=$(g ip -4 -o addr show lima0 | awk '{print $4}' | cut -d/ -f1)
if [ -n "$GUEST_IP" ]; then
  ok "lima0 = $GUEST_IP"
  info "dev servers will be at http://$GUEST_IP:<port>"
  info "re-run after a stop/start to confirm the IP is stable"
else
  bad "no IPv4 on lima0 - vzNAT may not be attached"
fi

echo
echo "[5] Root filesystem type and mount options"
FSTYPE=$(g findmnt -no FSTYPE /)
OPTS=$(g findmnt -no OPTIONS /)
info "fstype: $FSTYPE"
info "options: $OPTS"
# noatime eliminates the atime write-on-read overhead that would otherwise
# double I/O on every git status, compiler pass, or node_modules scan.
echo "$OPTS" | tr ',' '\n' | grep -qx noatime \
  && ok "noatime active (atime write-on-read suppressed)" || bad "noatime NOT active"

echo
echo "[6] Tuning sysctls applied"
# vm.vfs_cache_pressure=50
#   Default is 100. At 50 the kernel is half as eager to evict directory and
#   inode caches, keeping them in RAM longer. Repeated git, find, and ls calls
#   over large trees (e.g. node_modules) hit memory instead of disk.
#
# fs.inotify.max_user_watches=524288
#   Default is 8192-131072 depending on distro. Each file watcher (Vite,
#   webpack, Jest, editors) consumes one watch slot. Large monorepos easily
#   exhaust the default, producing "ENOSPC" inotify errors. 524288 (512K) is
#   the standard dev-machine recommendation.
for kv in "vm.vfs_cache_pressure=50" "fs.inotify.max_user_watches=524288"; do
  k="${kv%%=*}"; want="${kv##*=}"; got=$(g sysctl -n "$k")
  [ "$got" = "$want" ] && ok "$k=$got" || bad "$k=$got (expected $want)"
done

echo
echo "[7] fstrim (returns freed guest blocks to the sparse host image)"
# The guest disk image on the host is a sparse file: blocks are only allocated
# on the host filesystem as the guest writes to them.  When the guest deletes
# files, the ext4 blocks are marked free inside the image but the host has no
# way to know — the raw file stays large.
#
# fstrim (TRIM/DISCARD) bridges that gap: it tells the virtual block device
# which guest blocks are now free, and the hypervisor punches holes in the
# sparse host file, reclaiming actual disk space on the Mac.
#
# fstrim.timer runs the trim weekly (systemd default), which is a reasonable
# cadence for a dev workstation.  Run 'sudo fstrim -av' manually after
# deleting large build artefacts or node_modules to reclaim space immediately.
g systemctl is-enabled fstrim.timer >/dev/null 2>&1 \
  && ok "fstrim.timer enabled" || bad "fstrim.timer not enabled"
info "host image allocation before trim (sparse: allocated, not declared):"
# vz names the image 'disk'; qemu uses diffdisk/*.raw/*.qcow2. Listing all of
# them keeps this correct if vmType ever changes.
du -h ~/.lima/"$INSTANCE"/disk ~/.lima/"$INSTANCE"/diffdisk \
  ~/.lima/"$INSTANCE"/*.raw ~/.lima/"$INSTANCE"/*.qcow2 2>/dev/null \
  | sed 's/^/        /' || true
info "run 'sudo fstrim -av' in the guest, then compare"

echo
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ] || exit 1
