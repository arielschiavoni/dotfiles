# devbox

Linux development VM on macOS, managed by [Lima](https://lima-vm.io/).

## Why

macOS APFS is already slower than Linux ext4 for filesystem-heavy workloads,
but the real cost comes from all the processes on a typical work machine that
intercept every filesystem event — antivirus scanners, corporate security
agents, backup daemons, cloud sync clients, and developer tools like Spotlight
and FSEvents consumers all get a slice of every `open`, `stat`, and `unlink`.
That overhead stacks up so badly that the cost of virtualization becomes
irrelevant by comparison: the VM is still orders of magnitude faster.

Benchmarked with [disk-perf-git-and-pnpm](https://github.com/NullVoxPopuli/disk-perf-git-and-pnpm)
(run `./scripts/benchmark.sh` to reproduce inside the VM):

| Operation             | macOS host (M1 Pro) | Guest VM (this machine) | Bare-metal Linux (Ryzen 5) |
| --------------------- | ------------------: | ----------------------: | -------------------------: |
| `git clean -Xfd`      |    2m34s (baseline) |   4.3s (**36× faster**) |        3s (**51× faster**) |
| `pnpm install` (warm) |    3m28s (baseline) |  19.4s (**11× faster**) |       15s (**14× faster**) |

## Layout

```
devbox/
├── lima.yaml              # Ubuntu 26.04 VM definition
├── provision/
│   ├── 00-system.sh       # root: apt upgrade, fstrim, noatime, sysctls, mise
│   ├── 20-user.sh         # user: dotfiles, mise install, fish login shell
│   └── mise.toml          # tool versions (source of truth)
└── scripts/
    ├── create.sh           # host setup + start VM + stream provisioning output
    ├── upgrade.sh          # in-guest: pull dotfiles + re-run provisioning
    ├── destroy.sh          # destroy VM
    ├── ssh-config.sh       # emit ~/.ssh/config block
    ├── benchmark.sh        # timed git clean + pnpm install
    ├── snapshot.sh         # APFS clonefile snapshot
    └── verify.sh           # verification checklist
```

`create.sh` runs on the Mac; `upgrade.sh` runs inside the VM. Everything else
runs on the Mac.

## VM

| Setting     | Value                                          |
| ----------- | ---------------------------------------------- |
| Base        | Ubuntu 26.04 LTS aarch64                       |
| VM type     | `vz` (Apple Virtualization.framework)          |
| CPUs / RAM  | 6 / 16GiB                                      |
| Disk        | 100GiB sparse                                  |
| Network     | `vzNAT` (stable guest IP, reachable from host) |
| Guest user  | `devbox` (`$HOME` = `/home/devbox.guest`)      |
| Shell       | fish (via mise)                                |
| Share mount | `~/share` (host) ↔ `~/share` (guest), virtiofs |

## Tools

Language runtimes, CLI tools, and dev utilities are managed by
[mise](https://mise.jdx.dev/). See `provision/mise.toml` for the current list.

Add or remove tools by editing `mise.toml` and running `mise install` inside
the VM, or `./scripts/upgrade.sh` to apply every pending change at once.

## Usage

### First run

```bash
./scripts/create.sh
```

Starts the VM and streams provisioning output. Takes several minutes on first
boot while mise downloads tool binaries.

### SSH config

```bash
./scripts/ssh-config.sh   # paste output into ~/.ssh/config
```

The SSH port is fixed at `60022` in `lima.yaml`, so this block survives
destroy + create cycles. You only need to run this once.

### First boot: secrets setup

Secrets are managed with gopass, encrypted with your personal GPG key.
This is a one-time manual setup after every `create.sh` run.

**On the Mac (host):**

1. Export your personal GPG private key to the shared folder:
   ```bash
   gpg --export-secret-keys --armor arielschiavoni@gmail.com > ~/share/gpg-key.asc
   ```

**Inside the VM (`ssh devbox`):**

2. Import the GPG private key:

   ```bash
   gpg --import ~/share/gpg-key.asc
   ```

3. Set ultimate trust on the key:

   ```bash
   gpg --edit-key arielschiavoni@gmail.com
   # at the gpg> prompt:
   trust
   # choose 5 (ultimate)
   save
   ```

4. Verify the trust level is correct (should show `[ultimate]`):

   ```bash
   gpg --list-keys
   ```

5. Initialize gopass and clone the personal store (use your `GITHUB_PAT` as the password when prompted):

   ```bash
   gopass init
   gopass clone https://github.com/arielschiavoni/passwords.git personal
   ```

6. Verify decryption works:
   ```bash
   gopass show personal/dotfiles/shell-env
   ```

**Back on the Mac (host):**

7. Delete the exported key immediately:
   ```bash
   rm ~/share/gpg-key.asc
   ```

From now on, opening a new shell in the devbox will automatically load all secrets
from gopass into the environment.

### Daily

```bash
ssh devbox
```

### Upgrade

After changing `provision/00-system.sh`, `provision/20-user.sh`,
`provision/mise.toml`, the stow package list, or anything under `tools/`, apply
it to the running VM from inside the VM:

```bash
ssh devbox
~/repos/arielschiavoni/dotfiles/devbox/scripts/upgrade.sh
```

It pulls the dotfiles repo and re-runs both provision scripts against the
pulled copy, leaving the VM in the state a fresh `create.sh` would produce. It
is safe to run at any time; every step re-converges rather than recording that
it has run.

| Flag                 | Effect                                                     |
| -------------------- | ---------------------------------------------------------- |
| `--skip-apt-upgrade` | Skip `apt-get upgrade`. Everything else still converges.   |
| `--skip-pull`        | Provision from the working tree as it stands, without git. |

Note that **rebooting does not do this.** Lima inlines the provision scripts
into `~/.lima/devbox/lima.yaml` when the instance is created, so every later
boot re-runs that frozen snapshot rather than the files in this repo. Boot is
also the one path that skips `apt-get upgrade` by default, to keep
`limactl start` fast — `upgrade.sh` runs it unless told otherwise.

### Reaching the Mac: links and clipboard

The guest is headless and provides neither of the two commands terminal tools
reach for, so pressing `o` on a pull request in lazygit fails with
`fish: Unknown command: xdg-open` and `Ctrl+V` in opencode pastes nothing.

[`tools/crates/devbox-bridge`](../tools/crates/devbox-bridge/) supplies both
names in the guest, each forwarding to one small daemon on the Mac:

| In the guest | Talks to the Mac's | Fixes                                                              |
| ------------ | ------------------ | ------------------------------------------------------------------ |
| `xdg-open`   | `open`             | lazygit `o`, `nvim gx`, `gh browse`, anything honouring `$BROWSER` |
| `xclip`      | `pngpaste`         | `Ctrl+V` image paste in opencode and Claude Code                   |

Supplying the command names is the whole trick — no lazygit or agent
configuration anywhere.

Both ends bind loopback only; the guest reaches the Mac through a
`RemoteForward` in the `~/.ssh/config` block below, which exists only for the
lifetime of an `ssh devbox` session. A `limactl shell devbox` session has no
tunnel by design.

Setup is handled by `./scripts/create.sh` (which is safe to re-run on an
existing VM — the host half lives above its early exit) plus the SSH config
block. To check it:

```bash
devbox-bridge --status           # on the Mac: loaded? listening? pngpaste found?
ssh devbox                       # then, inside the VM:
xdg-open https://example.com     # should open on the Mac
xclip -selection clipboard -t TARGETS -o   # prints image/png if you copied one
```

That last command is also the cheapest health check: exit `1` with no output
means the tunnel works and you simply have no image copied, while exit `2`
means the bridge is broken.

If something fails, both clients name every possible cause — though the agents
discard `xclip`'s stderr, so run it by hand to see why. After editing the crate,
reload the Mac side with `./scripts/create.sh` and rebuild the guest side with
`./scripts/upgrade.sh` in the VM.

Two things to know. URLs must be pure ASCII: a raw umlaut or space is rejected
with a message telling you to percent-encode it. And anything running in the VM
can read your Mac clipboard while the SSH session is up — fine for a local
single-user VM, but it is a real capability. The crate's README covers both.

### Transfer files

`~/share` is mounted via virtiofs on both sides. Use it for occasional file
transfers (archives, build artifacts) only — not for development work (see
below).

### Destroy

```bash
./scripts/destroy.sh   # prompts for confirmation; ~/share on the host is untouched
```
