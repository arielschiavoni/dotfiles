# dotfiles

## Install

### Darwin (MacOS)

```bash
cd ./install/darwin/
./install.sh
```

### Linux

```bash
cd ./install/linux/
./install.sh
```

## Configure

The config script automatically detects the OS and creates the corresponding configuration for
the tools relevant to the OS. It uses `stow`.

```bash
cd ./config/
./config.sh
```

### Agent skills (`~/.agents`)

The `config/agents` package stows to `~/.agents`, which holds agent skills and
the `npx skills` lock file (`.skill-lock.json`). The whole tree is versioned so
skills installed via `npx skills add` and their updates show up as git diffs.

> [!IMPORTANT]
> On a new machine, run `./config.sh` **before** running `npx skills` or any
> agent that touches `~/.agents`. Stow only folds `~/.agents` into a symlink
> when the directory does not yet exist; if a tool creates a real `~/.agents`
> first, stow will report a conflict and the skills will not be tracked.

## Fish Shell Configuration

```
~/.config/fish/
├── conf.d/        # All configuration. Sourced in filename order, before config.fish
├── functions/     # One function per file, lazily autoloaded on first call
├── scripts/       # Helper scripts invoked by functions (e.g. aws_session_remaining.py)
└── config.fish    # Intentionally empty; documents the conf.d contract
```

### Load order

The numeric prefix on each `conf.d` file **is** the contract — it encodes load
order, not category:

| File              | Purpose                                             |
| ----------------- | --------------------------------------------------- |
| `00-brew.fish`    | Homebrew env (macOS). **Must** precede `20-path`.   |
| `01-mise.fish`    | mise activation. **Must** precede `40-tools`.       |
| `10-env.fish`     | Environment variables. May not depend on `PATH`.    |
| `20-path.fish`    | Every `PATH` entry, in one explicit order.          |
| `30-secrets.fish` | gopass-backed secrets.                              |
| `40-tools.fish`   | _interactive_ — prompt, history, directory jumping. |
| `50-abbr.fish`    | _interactive_ — abbreviations.                      |
| `60-theme.fish`   | Colours for fish and fzf.                           |

Two ordering constraints are load-bearing: Homebrew must be on `PATH` before
`20-path` reorders it, and mise must have activated before `40-tools` runs,
because in the devbox starship/zoxide/atuin are mise-managed and are not on
`PATH` until then.

`20-path.fish` owns **every** `PATH` entry. Previously each snippet called
`fish_add_path --prepend` independently, which made precedence the reverse of
conf.d's alphabetical filename order — so renaming a file silently reordered
`PATH`. It also uses `--path` rather than the default `$fish_user_paths`, since
fish splices that list ahead of `$PATH` regardless of what any config declares.

### Interactive guard

Files marked _interactive_ begin with `status is-interactive; or exit`, which
stops that file only — it does not terminate the shell. (Inside a _function_,
`exit` **would** terminate the shell.)

This matters because fish sources its config for **every** shell, including
`fish -c`. tmux and kitty popups run `fish -c <function>`, and they need no
prompt, history daemon or directory-jump hook. Skipping those removes ~28ms per
invocation.

### Why `functions/` is one file per function

Files in `functions/` are lazily autoloaded on first call. Defining all of them
eagerly — by moving them into `config.fish` — costs **~21ms on every shell
start**, and would also break `funced`/`funcsave` and edit-without-reload. The
file count is a cache index, not clutter.

### Startup cost

Two costs are avoided deliberately, both measured on macOS where two Endpoint
Security extensions hook every `exec`:

- **`brew shellenv` (140–180ms).** `00-brew.fish` hardcodes its six constant
  output lines instead of shelling out.
- **Tool inits (~26ms combined).** `functions/__init_cached.fish` caches the
  output of `starship`/`zoxide`/`atuin` init, invalidating on the binary's
  mtime — so a brew or mise upgrade regenerates automatically, with no manual
  rebuild step.

Absolute startup times drift with machine load, so the stable measure is the
cost _this config adds_ over `fish --no-config`:

| Scenario                          | Added by this config                               |
| --------------------------------- | -------------------------------------------------- |
| `fish -c` from a tmux/kitty popup | **~28ms** (was ~65ms before the interactive guard) |
| Interactive startup               | ~56ms                                              |

Benchmark with `date`-based timing inside fish and it will over-report by
7–11ms per sample, because spawning `date` costs about that much here. Compare
whole-process runs instead.

Reload everything with `fish_reload` (`alt-r`, or the `sf` abbreviation). It
`exec`s a new fish, so `set -gx` deletions still require a fresh terminal.
