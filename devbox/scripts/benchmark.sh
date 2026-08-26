#!/usr/bin/env bash
# Phase 1 gate: does the VM actually beat the macOS baseline?
# Usage: ./benchmark.sh [instance]   e.g. ./benchmark.sh devbox
#
# macOS baseline on this host:
#   git clean -Xfd : 2m34s  (user 1.5s,  sys 59s)
#   pnpm install   : 3m28s  (user 36s,   sys 3m26s)
#
# Bare-metal Linux reference (older Ryzen 5): 3s / 15s.
set -euo pipefail

INSTANCE="${1:-${DEVBOX_INSTANCE:-devbox}}"
REPO_URL="${REPO_URL:-https://github.com/NullVoxPopuli/disk-perf-git-and-pnpm}"
WORK="devbox/disk-perf-git-and-pnpm"

echo "=== devbox benchmark (instance: $INSTANCE) ==="
echo "baseline (macOS): git clean 2m34s | pnpm install 3m28s"
echo

limactl shell "$INSTANCE" -- bash -lc "
set -euo pipefail

command -v git  >/dev/null || { echo 'git missing'; exit 1; }
command -v pnpm >/dev/null || { echo 'pnpm missing - run mise install first'; exit 1; }

if [ ! -d \"\$HOME/$WORK\" ]; then
  echo '==> cloning benchmark repo (guest-native)'
  git clone --quiet '$REPO_URL' \"\$HOME/$WORK\"
fi

cd \"\$HOME/$WORK\"

echo '==> df -i before'
df -i . | tail -1

if [ ! -d node_modules ]; then
  echo
  echo '==> priming: first install (not timed, populates pnpm store)'
  pnpm install --silent >/dev/null 2>&1 || pnpm install
fi

echo
echo '==> TIMED: git clean -Xfd; git clean -fd'
time { git clean -Xfd >/dev/null; git clean -fd >/dev/null; }

echo
echo '==> TIMED: pnpm install (warm store)'
time pnpm install >/dev/null 2>&1

echo
echo '==> df -i after'
df -i . | tail -1
df -h . | tail -1
"

echo
echo "=== host-side disk image allocation ==="
DISK=~/.lima/"$INSTANCE"/disk
ls -lh "$DISK" 2>/dev/null | awk '{print "  apparent: "$5"  "$9}'
du -h "$DISK" 2>/dev/null | awk '{print "  actual:   "$1"  "$2}'
