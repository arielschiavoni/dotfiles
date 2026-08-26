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
    ├── create.sh           # start VM + stream provisioning output
    ├── destroy.sh          # destroy VM
    ├── ssh-config.sh       # emit ~/.ssh/config block
    ├── benchmark.sh        # timed git clean + pnpm install
    ├── snapshot.sh         # APFS clonefile snapshot
    └── verify.sh           # verification checklist
```

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
the VM (or rebooting — provisioning runs on every boot).

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

### Daily

```bash
ssh devbox
```

### Transfer files

`~/share` is mounted via virtiofs on both sides. Use it for occasional file
transfers (archives, build artifacts) only — not for development work (see
below).

### Destroy

```bash
./scripts/destroy.sh   # prompts for confirmation; ~/share on the host is untouched
```
