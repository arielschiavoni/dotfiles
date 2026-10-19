# darwin install

`install.sh` sets up a new Mac and upgrades an existing one. Every step checks
its own state first, so it is safe to run at any time.

## New Mac

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/arielschiavoni/dotfiles/main/install/darwin/install.sh)"
```

The Homebrew installer brings the Xcode Command Line Tools (and with them
`git`). The script then clones the dotfiles to `~/repos/arielschiavoni/dotfiles`
and continues with that copy.

Afterwards, by hand:

1. Sign in to 1Password, import the GPG key and set up gopass (same steps as
   the devbox README, run on the Mac). Secrets and `GITHUB_TOKEN` load from the
   next fish shell on.
2. Re-run `install.sh` for the steps that needed a GitHub token (gh
   extensions).
3. Log out and back in for the keyboard settings.

## Upgrade

```sh
~/repos/arielschiavoni/dotfiles/install/darwin/install.sh
```

It pulls the repo, re-runs itself from the pulled copy, and converges:

| Step           | What it does                                                               |
| -------------- | -------------------------------------------------------------------------- |
| Homebrew       | Installed if missing; `brew update`, `brew bundle install` (upgrades too)  |
| Rust           | `rustup` installed or updated; `tools/crates` built, retired ones removed  |
| devbox-bridge  | launchd agent (re)loaded, so links and image paste work once a VM exists   |
| Config         | Broken links into `config/` removed, packages stowed one at a time         |
| Shell          | `/opt/homebrew/bin/fish` in `/etc/shells` and set as login shell           |
| Plugins        | tpm and tmux plugins, yazi plugins, gh extensions                          |
| macOS settings | Keyboard, Finder, Dock, no animations; only differing values are written   |
| macOS updates  | Listed only: `sudo softwareupdate --install --all --restart` to apply them |

| Flag              | Effect                                                            |
| ----------------- | ----------------------------------------------------------------- |
| `--skip-pull`     | Run from the working tree as it stands, without git.              |
| `--skip-upgrade`  | Install what is missing, upgrade nothing, skip the update check.  |
| `--skip-defaults` | Leave macOS settings alone.                                       |
| `--cleanup`       | Uninstall Homebrew packages missing from the Brewfile (else list) |

A failing step does not stop the run; failures are listed at the end and the
script exits `1`. Precondition errors (dirty tree, run as root) exit `2`.

## Brewfile

Homebrew packages, casks and crates.io tools, and the source of truth for
them. The crates in `tools/crates` are not in it: `install.sh` builds them
from source, and `brew bundle cleanup` runs with `--no-cargo` so it never
lists them.

### Add and remove packages

Two fish functions keep this Mac and the `Brewfile` in step:

```sh
brewadd ripgrep              # formula, or cask when no formula has the name
brewadd --cask ghostty       # force the cask
brewadd anomalyco/tap/foo    # declares the tap too
brewrm ripgrep
```

Each changes the `Brewfile` only after brew has done its part:

- `brewadd` runs `brew install`, then `brew bundle add` (with a
  description comment) for what installed. A failed install leaves the file
  untouched.
- `brewrm` runs `brew uninstall`, then `brew bundle remove` once the package
  is gone. A refused uninstall, such as another package depending on it, keeps
  the entry. A package that is not installed only loses its entry.

Commit the `Brewfile` afterwards. A `Brewfile` edited by hand needs
`install.sh --skip-pull` (a dirty tree blocks the pull) or
`brew bundle install --file <Brewfile> --no-upgrade` to apply it.

### Installed with plain `brew install`

Every `install.sh` run lists installed packages missing from the `Brewfile`.
`brewadd <name>` on an installed package just adds its entry.

`brew bundle dump --describe --force` regenerates the whole file from the
Mac instead. Review the diff: it also picks up every ad hoc install, adds
`cargo` lines for the `tools/crates` binaries (delete them; those names do not
exist on crates.io) and may reorder entries.

## How to Downgrade a Homebrew Package

Homebrew taps (like `sst/tap`) use a single rolling formula file — there are no versioned formulas kept around. To install an older version you need to temporarily check out the formula file at the commit that introduced that version, reinstall, then pin to prevent auto-upgrade.

### Example: downgrade opencode from `1.16.0` to `1.15.13`

**1. Find the commit for the version you want**

```sh
git -C /opt/homebrew/Library/Taps/sst/homebrew-tap log --oneline opencode.rb
```

This lists every commit that touched `opencode.rb`. Find the one that says `Update to v1.15.13` — its SHA is `d81638f`.

**2. Check out the formula at that commit**

```sh
git -C /opt/homebrew/Library/Taps/sst/homebrew-tap checkout d81638f -- opencode.rb
```

This replaces only the formula file on disk. The repo stays on its current branch.

**3. Reinstall**

```sh
brew reinstall sst/tap/opencode
```

**4. Pin to prevent auto-upgrade**

```sh
brew pin opencode
```

Without this, `brew upgrade` would immediately pull the latest version back down.

### Re-upgrading when the bug is fixed

**1. Restore the formula to latest**

```sh
git -C /opt/homebrew/Library/Taps/sst/homebrew-tap checkout HEAD -- opencode.rb
```

**2. Unpin and upgrade**

```sh
brew unpin opencode && brew upgrade opencode
```
