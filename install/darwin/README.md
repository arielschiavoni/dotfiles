# darwin install

Homebrew packages, casks, and VS Code extensions managed via `Brewfile`.

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
