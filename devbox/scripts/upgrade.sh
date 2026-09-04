#!/usr/bin/env bash
# Bring this devbox up to the state a fresh create.sh would produce.
#
# Run this INSIDE the guest. It pulls the dotfiles repo and re-runs both
# provision scripts from the pulled copy, so a change to provision/*.sh,
# mise.toml, the stow package list, or tools/ reaches an existing VM without
# destroying and re-creating it.
#
# WHY THIS EXISTS RATHER THAN "just reboot": Lima inlines the provision scripts
# into ~/.lima/devbox/lima.yaml when the instance is created. Every later boot
# re-runs that frozen snapshot, not the files in this repo, so a reboot cannot
# pick up edits made after create.
set -euo pipefail

DOTFILES_DIR="$HOME/repos/arielschiavoni/dotfiles"

APT_UPGRADE=1
SKIP_PULL=0

usage() {
  cat << 'EOF'
Usage: upgrade.sh [--skip-apt-upgrade] [--skip-pull]

Re-runs the devbox provision scripts against the current dotfiles checkout.

  --skip-apt-upgrade  Skip `apt-get upgrade`. The package list, mise tools,
                      stow links and everything else still converge; this only
                      drops the slow distribution upgrade.
  --skip-pull         Do not touch git. Use when testing local edits to the
                      provision scripts, or on a dirty working tree.
  -h, --help          Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-apt-upgrade) APT_UPGRADE=0 ;;
    --skip-pull) SKIP_PULL=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "upgrade.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log() { echo "==> $*"; }

# ---------------------------------------------------------------------------
# Guard: this must not run on the Mac.
#
# 00-system.sh would call apt-get and edit /etc/fstab, and 20-user.sh would
# chsh your real user. /var/lib/devbox is created by 00-system.sh and exists
# only inside the guest.
# ---------------------------------------------------------------------------
if [ ! -d /var/lib/devbox ]; then
  echo "ERROR: this script only runs inside the devbox guest." >&2
  echo "       From the Mac:  ssh devbox   then re-run it there." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Guard: do NOT run this under sudo.
#
# It escalates on its own, for the one script that needs it. Run as root and
# sudo resets HOME to /root, so DOTFILES_DIR points at a checkout that does not
# exist - and if it did, stow would symlink into /root, mise and cargo would
# install into root's home, and chsh would change root's login shell.
#
# Checked before the checkout test below, which would otherwise blame a missing
# clone and advise re-creating the VM.
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: do not run this with sudo - run it as your normal user." >&2
  echo "       It calls sudo itself for the system half of provisioning." >&2
  exit 1
fi

if [ ! -d "$DOTFILES_DIR/.git" ]; then
  echo "ERROR: no dotfiles checkout at $DOTFILES_DIR" >&2
  echo "       This VM was never provisioned. Re-create it with create.sh." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# GitHub token
#
# 20-user.sh needs one for mise, to avoid GitHub's 60 req/hour anonymous limit.
# An `ssh devbox` session already has it: fish exports it from gopass in
# conf.d/30-secrets.fish. A `limactl shell` session does not, because that runs
# bash and bash never reads fish's conf.d - so recover it directly from gopass.
#
# Left empty if that fails too: 20-user.sh reports a missing token with better
# advice than could be duplicated here.
# ---------------------------------------------------------------------------
if [ -z "${GITHUB_TOKEN:-}" ] && command -v gopass > /dev/null 2>&1; then
  log "GITHUB_TOKEN not in the environment - reading it from gopass"
  GITHUB_TOKEN="$(gopass show personal/dotfiles/shell-env 2> /dev/null \
    | sed -n 's/^GITHUB_TOKEN=//p' | head -1)" || true
fi
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ---------------------------------------------------------------------------
# Pull, then hand over to the pulled copy of this script.
# ---------------------------------------------------------------------------
if [ "$SKIP_PULL" -eq 0 ]; then
  if ! git -C "$DOTFILES_DIR" diff --quiet \
    || ! git -C "$DOTFILES_DIR" diff --cached --quiet; then
    echo "ERROR: $DOTFILES_DIR has uncommitted changes." >&2
    echo "       Commit or stash them, or re-run with --skip-pull to" >&2
    echo "       provision from the working tree as it stands." >&2
    exit 1
  fi

  BEFORE="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
  log "pulling dotfiles"
  git -C "$DOTFILES_DIR" pull --ff-only
  AFTER="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"

  if [ "$BEFORE" != "$AFTER" ]; then
    git -C "$DOTFILES_DIR" --no-pager log --oneline "$BEFORE..$AFTER" \
      | sed 's/^/    /'

    # This script may itself be one of the files that just changed. Re-exec the
    # new copy so the orchestrator and the provision scripts it drives are the
    # same generation. --skip-pull terminates the recursion.
    log "re-running the pulled upgrade.sh"
    REEXEC=(--skip-pull)
    if [ "$APT_UPGRADE" -eq 0 ]; then
      REEXEC+=(--skip-apt-upgrade)
    fi
    # Via `bash` rather than executing it directly, so this does not depend on
    # the exec bit surviving the pull.
    exec bash "$DOTFILES_DIR/devbox/scripts/upgrade.sh" "${REEXEC[@]}"
  fi

  log "dotfiles already up to date"
fi

# ---------------------------------------------------------------------------
# Provision, in the same order Lima runs them on boot.
#
# `sudo VAR=value` passes the variable through as part of the command line, so
# no sudoers env_keep entry is needed.
# ---------------------------------------------------------------------------
log "running 00-system.sh (apt upgrade: $([ "$APT_UPGRADE" -eq 1 ] && echo yes || echo no))"
sudo DEVBOX_APT_UPGRADE="$APT_UPGRADE" \
  bash "$DOTFILES_DIR/devbox/provision/00-system.sh"

log "running 20-user.sh"
bash "$DOTFILES_DIR/devbox/provision/20-user.sh"

echo
log "devbox upgraded."
echo "    Open a new shell to pick up PATH, fish and tool changes."
echo "    In a running tmux session:  prefix + I  reloads plugins."
