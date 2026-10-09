# AGENTS.md

Dotfiles for macOS and a Linux devbox VM (Lima).

## Layout

- `config/<pkg>/` - stowed into `$HOME` (`config/config.sh`). The links are live: an edit here changes the running config at once (`~/.pi` → `config/pi/.pi`).
- `tools/` - Rust workspace, kept out of stow; binaries go to `~/.cargo/bin`. See `tools/README.md`.
- `devbox/` - VM definition and provisioning (`provision/*.sh`); `install/` - per-OS installers.

## Rust (`tools/`)

- Check: `cargo fmt --all && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace`
- Install: `cargo install --path crates/<name> --locked --force`. A config change in `config/` may need the new binary right away (cred-broker rejects unknown keys), then `cred-broker restart`.
- Exit codes: `0` ok, `1` expected negative, `2` failure.

## Style

- Formatters: `prettier` (JS/TS/JSON/YAML/Markdown), `stylua` (Lua, 2 spaces), `fish_indent`, `rustfmt`, `ruff`.
- Comments: minimal; explain why, in the crate's existing tone.
- Docs and comments describe what the code does, not what it doesn't do or avoids ("reads the config directly", not "without the CLI").

## Git

- `main`, rebase on pull. The user may stage changes while you work: leave the index alone, and commit only when asked.
