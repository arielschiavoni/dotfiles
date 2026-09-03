# tools

Small command line utilities written in Rust, compiled to standalone binaries
and installed into `~/.cargo/bin`.

## Why this directory is not under `config/`

`config/config.sh` runs GNU Stow over **every** directory in `config/`, which
symlinks its contents into `$HOME`. That is right for dotfiles and wrong for
source code: a Rust crate here would leak `Cargo.toml`, `Cargo.lock` and a
multi-gigabyte `target/` into your home directory. The previous TypeScript
version of `find-old-python` lived in `config/bin/` and was one `stow` run away
from doing exactly that with `package.json` and `node_modules/`.

Keeping `tools/` a sibling of `config/` sidesteps the problem entirely. Nothing
here is stowed; `cargo install` copies finished binaries to `~/.cargo/bin`,
which is already on `PATH`.

## Layout

```
tools/
├── Cargo.toml              virtual manifest — the workspace root
├── Cargo.lock              committed, so builds are reproducible
└── crates/
    ├── devbox-open-url/    open URLs from the devbox VM in the macOS browser
    └── find-old-python/    one directory per tool
```

`devbox-open-url` is the one crate here that is built for **two** platforms: its
daemon runs on the macOS host and its `xdg-open` client runs inside the Linux
guest, so each is installed separately with `--bin`. See its README.

## Building and installing

```sh
# everything
for d in crates/*/; do cargo install --path "$d" --locked; done

# just one
cargo install --path crates/find-old-python --locked
```

During development the usual commands work from this directory:

```sh
cargo build                 # all members
cargo build -p find-old-python
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all
```

## Adding a tool

```sh
cargo new crates/my-tool
```

That is the whole procedure. The workspace declares `members = ["crates/*"]`,
so the glob picks up the new directory with no edit to `tools/Cargo.toml`.

In the new crate's `Cargo.toml`, inherit the shared settings:

```toml
[package]
name = "my-tool"
version.workspace = true
edition.workspace = true

[dependencies]
clap = { workspace = true }
```

Shared dependency versions live in `[workspace.dependencies]` at the root, so
two tools can never drift onto different versions of the same crate by
accident. A tool that needs something unique just declares it normally.

## Why a workspace rather than one crate with several binaries

A single crate with `src/bin/*.rs` would be less setup, but Cargo resolves
dependencies per _package_, not per _binary_. One tool pulling in a heavy
dependency would mean every build compiles it, even for unrelated tools. Two
tools could also never depend on different major versions of the same crate —
there is no workaround for that in a single crate.

Workspace members still share one `target/` directory, so a dependency used by
two tools is compiled once and reused.

## Conventions

- Edition 2024, formatted with `rustfmt`, linted with `clippy -D warnings`
- Prefer the standard library; add a dependency only when it removes real work
- Exit `0` on success, `1` on an expected negative result, `2` on tool failure,
  so the binaries compose in shell scripts and CI
- Detect whether stdout is a terminal before emitting ANSI colour
