# find-old-python

Scans macOS for Python interpreters older than a version threshold, reports how
to get rid of each one, and optionally removes the ones that are safe to delete.

The corporate policy this exists for allows Python **3.13.x**, so the default
threshold is `--below 3.13`.

## Usage

```sh
find-old-python                     # report anything below 3.13
find-old-python --below 3.12        # different threshold
find-old-python --verbose           # also list libraries and non-executables
find-old-python --clean             # remove what is safe, prompting each time
find-old-python --clean --yes       # same, unattended
find-old-python --root /Applications
find-old-python --exclude /.cache/  # skip paths containing a substring
```

| Flag | Meaning |
| --- | --- |
| `--below <VERSION>` | Threshold, exclusive. Default `3.13`. |
| `--clean` | Delete removable violations and broken symlinks. |
| `--yes` | Skip confirmation prompts. |
| `--verbose` | Also show shared libraries and non-executable matches. |
| `--root <PATH>` | Replace the default roots. Repeatable. |
| `--exclude <SUBSTRING>` | Prune any path containing this text. Repeatable. |
| `--exhaustive` | Scan all of `$HOME` instead of the default targeted subdirectories. |
| `--threads <N>` | Walker threads; `0` means one per core. |

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Compliant — no violations |
| `1` | Violations found, or still present after `--clean` |
| `2` | Tool error |

Only **violations** affect the exit code. Broken symlinks, shared libraries and
non-executable matches never do.

## What gets scanned

There are two modes.

**Default — targeted roots.** Outside `$HOME`, whole directories that are
themselves install locations:

```
/Library  /opt  /usr  /Applications
```

`/usr` already covers `/usr/local`. macOS grafts `/usr/local` in from the Data
volume via a firmlink, and although `statfs` reports a different filesystem ID
either side of the graft, `lstat` reports the *same* `st_dev` — which is what
the directory walker actually compares. Listing `/usr/local` separately only
walks it twice.

Inside `$HOME`, an explicit list of subdirectories rather than `$HOME` itself:

```
~/Library  ~/.cache/uv  ~/.local/share/uv  ~/.local/bin
~/Applications  ~/.Trash
~/.pyenv  ~/.asdf  ~/.rye  ~/.conda  ~/.lmstudio
~/miniconda3  ~/anaconda3  ~/miniforge3  ~/mambaforge
```

Paths that don't exist are skipped silently and cost nothing — the version
managers are listed even though none are installed on a typical machine, so
installing one tomorrow is covered with no code change.

**`--exhaustive` — full `$HOME`.** Replaces the subdirectories above with bare
`$HOME`, walked in full. The four outside-`$HOME` roots are unchanged.

### Why targeted roots instead of a denylist

An earlier version of this tool pruned known-noisy trees (`node_modules`,
`.git`, package-manager caches) from a full `$HOME` walk instead. Measurement
showed that was solving the wrong problem: of the 72 Python-named paths found
anywhere under `$HOME` on a real machine, **68 were symlinks**, and 63 of
those resolved to a single binary already reachable directly via `/opt`. Only
**4 real files** existed anywhere in `$HOME` outside the targeted list — all
inside `~/.Trash`, which is on it. Walking millions of entries under `$HOME`
was earning exactly one unique finding that the targeted roots also catch, in
a fraction of the time:

| Scan | Entries | Time | Violations |
| --- | --- | --- | --- |
| Default (targeted roots) | 2.80M | 23s | 3 |
| `--exhaustive` (full `$HOME`) | 8.32M | 53s | 3 |

`~/Library` is listed as a whole rather than as `~/Library/Application Support`
and `~/Library/Python` separately — it already contains both, and listing a
directory alongside its own descendant walks the descendant twice, the same
mistake `/usr` + `/usr/local` would be.

The known trade-off: a location this list has never heard of — a new app
vendoring its own Python under a novel dot-folder, the way LM Studio once did
under `~/.lmstudio` — will not be found by default. `--exhaustive` exists as
the periodic check against that; run it monthly, or in CI on a schedule.

The walk stays on each root's own device, so external drives, disk images and
network shares are never traversed. Unlike a `.gitignore`-aware search, hidden
files and ignored directories **are** searched — a compliance scan cannot skip
`.venv`.

App bundles are searched too. This matters: Inkscape ships its own Python 3.10
inside `Inkscape.app`, and the previous implementation excluded `*.app` and
therefore never saw it.

## How results are classified

| Bucket | Counts as a violation | Removed by `--clean` |
| --- | --- | --- |
| Interpreter below the threshold | yes | only if nothing else owns it |
| Broken symlink | no | yes |
| Shared library (`Python.framework/Python`) | no | never |
| Non-executable match (man pages, data) | no | never |

Every violation is counted, **including ones the tool cannot fix**, so the exit
code always reflects the true state of the machine. Each of those prints the
specific remediation instead:

```
3.10.0*   /Applications/Inkscape.app/…/bin/python3.10        app:Inkscape.app
          ↳ bundled in /Applications/Inkscape.app — uninstall the app; deleting this file breaks it
```

- **App-bundled** — uninstall the application. Deleting the file breaks it.
- **Already in the Trash** — the app was already uninstalled; empty the Trash to
  actually free the disk space. Checked before the app-bundle case, since a
  trashed `.app` is trash before it is anything else.
- **MDM-managed** (`/Library/ManagedFrameworks`) — escalate to IT. Do not delete.
- **System** (`/usr/bin`) — protected by SIP and cannot be removed.
- **Package-manager owned** — the exact command is printed, e.g.
  `brew uninstall python@3.11`, `pyenv uninstall 3.11.9`, `uv cache clean`.
  Deleting these files directly would leave the owner's manifest inconsistent,
  so `--clean` deliberately refuses.

A `*` after the version means it was read from the path rather than from the
binary, because macOS refused to execute it — see below.

## Two macOS details worth knowing

**The executable bit lies.** `Python.framework/Python` has the executable bit
set but is a Mach-O *shared library*. Trying to run it is not a reliable test
either: Rust's `Command` responds to an exec-format failure by silently
retrying through `/bin/sh`, which prints `"…/Versions/3.10/Python: cannot
execute binary file"` — and a naive version parse pulls `3.10` straight out of
the path inside that error message and invents a violation. The tool reads the
Mach-O header instead, which is deterministic and needs no subprocess.

**Bundled interpreters must not be run.** macOS library validation kills an
app-bundled Python the instant it is launched outside its own bundle, with
`SIGKILL (Code Signature Invalid)`. That is not a quiet failure — each attempt
raises a *"Python quit unexpectedly"* dialog and leaves a crash report in
`~/Library/Logs/DiagnosticReports`.

So interpreters inside a `.app` are never executed. Their version is read from
the path instead (`…/Versions/3.10/bin/python3` → `3.10`) and marked with `*`.
Nothing is lost by not running them: the remediation for a bundled Python is to
uninstall the application, never to delete the file.

The same `*` fallback covers any other binary that refuses to run, so a
violation is reported rather than silently dropped.

If an app-bundled interpreter has no version anywhere in its path, it is listed
as a non-executable match rather than executed. In practice framework layouts
always carry a `Versions/X.Y` directory.

The no-execute rule is structural — "is this file inside a `.app`?" — not based
on the remediation shown. An app sitting in the Trash still has its original,
still-signed binaries; only its *reported* fix text changes.

## Timing

Every run ends with a per-root breakdown of where the time went:

```
TIMING
ROOT                                    TIME        ENTRIES     CANDIDATES  
/Users/ariel/Library                    12.214s     1575726     0             (56.3% of entries)
                                        ↳ 19 path(s) denied while walking this root
/Users/ariel/.cache/uv                  6.533s      526218      54            (18.8% of entries)
/Library                                1.679s      191929      7             ( 6.9% of entries)
/Applications                           1.540s      287027      2             (10.2% of entries)
/opt                                    0.938s      174127      33            ( 6.2% of entries)
/usr                                    0.137s      23440       2             ( 0.8% of entries)
/Users/ariel/.Trash                     0.069s      14026       8             ( 0.5% of entries)
/Users/ariel/.local/share/uv            0.046s      8055        3             ( 0.3% of entries)
total (sum of roots)                    23.160s     2800570
```

`ENTRIES` is every file, directory and symlink the walker actually visited
under that root — the true cost of the traversal — while `CANDIDATES` is just
the Python-named subset that got classified. `~/Library` dominates even the
targeted scan (56% of it, on this machine), since it holds every app's support
files and caches; `--root` narrows further when iterating on the tool itself.

Roots are walked one after another rather than in one combined pool, purely so
each row's time is real wall-clock time for that root and not an estimate. The
walk *inside* a root is still fully parallel across `--threads` workers — only
the roots themselves don't overlap with each other.

## Notes

- `~/.cache/uv` contributes a lot of matches. They are symlinks into real
  interpreters that get scanned anyway, and they collapse to a single
  `--version` call each because probes are cached by canonical path. Clear them
  with `uv cache clean`, not by deleting files.
- Paths the scan could not read are counted and reported. Corporate security
  tooling and TCC-protected caches account for most of them. This is surfaced
  deliberately so that an incomplete scan cannot quietly report "compliant".
- `--exhaustive` takes roughly a minute; bare `$HOME` is the overwhelming
  majority of it. The default targeted-root scan takes roughly 20-25s. Narrow
  further with `--root` when iterating on the tool itself.

## Implementation sketch

A parallel directory walk (the `ignore` crate, the same walker behind `fd` and
`ripgrep`) visits the roots. Filenames are matched with a case-insensitive byte
comparison equivalent to `^python[0-9.]*$` — case folding is required, because
frameworks ship a binary named `Python` with a capital `P`.

Candidates are classified on the walker thread that found them, so running
`python --version` overlaps the walk instead of forming a second serial phase
after it. Findings travel to the main thread over an `mpsc` channel. Fewer than
a couple of hundred of several million visited entries are candidates, so the
expensive work is rare enough to sit directly in the hot path's slow lane.

```sh
cargo test -p find-old-python
```
