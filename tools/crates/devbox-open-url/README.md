# devbox-open-url

Open URLs from the [devbox VM](../../../devbox/) in the macOS default browser.

The guest is headless, so nothing there provides `xdg-open` — which is what
every terminal tool shells out to for links. Pressing `o` on a pull request in
lazygit used to fail with `fish: Unknown command: xdg-open`.

This crate ships a replacement `xdg-open` for the guest plus a daemon for the
Mac that calls `/usr/bin/open`. Providing that one command name fixes lazygit,
`nvim gx`, `gh browse` and anything honouring `$BROWSER` at once — in
particular, **no lazygit config change**: `os.openLink` stays empty and its
Linux default now resolves.

## How it works

```
guest (Ubuntu)                          │  mac (darwin)
lazygit `o`                             │
  → xdg-open <url>          ~/.cargo/bin│
      ├─ normalize() ◄── src/lib.rs ──► │ normalize()
      └─ TcpStream 127.0.0.1:17325      │     ▲
              └──── sshd RemoteForward ─┼─────┴─ devbox-open-url (LaunchAgent)
                                        │         → /usr/bin/open <url>
```

Both ends bind loopback only. The guest reaches the Mac exclusively through the
`RemoteForward` in the devbox `~/.ssh/config` block, which exists only for the
lifetime of an `ssh devbox` session — so a `limactl shell devbox` session has no
tunnel, by design, and the client says so when it cannot connect.

One newline-terminated line each way:

```
-> https://github.com/owner/repo/pull/42\n
<- OK\n                        (or)  ERR <reason>\n
```

## Binaries

| Binary            | Machine    | Installed by                                                           |
| ----------------- | ---------- | ---------------------------------------------------------------------- |
| `devbox-open-url` | macOS host | `devbox/scripts/create.sh`; `install/darwin/install.sh` on a fresh Mac |
| `xdg-open`        | guest VM   | `devbox/provision/20-user.sh`, on every boot                           |

```sh
devbox-open-url             # run the daemon (what launchd invokes)
devbox-open-url --install   # write the launchd plist and (re)load it
devbox-open-url --status    # installed? loaded? listening?
xdg-open <http(s)-url>      # send one URL to the Mac
```

`--install` lives in the binary because the plist must name an absolute path to
the program, and `std::env::current_exe` knows it — no `$HOME` expansion into
XML, and no stale-path bugs. It cannot run from Lima provisioning, which
executes inside the guest and has no access to `launchctl` on the Mac.

## Security properties

Any process in the VM can make the Mac open an `http`/`https` URL while an SSH
session is live. That is the intended capability, and it is bounded to exactly
that by two things:

- `normalize` requires an `http://` or `https://` prefix, so the URL cannot be a
  leading `-` that `open` reads as a flag, nor a bare path or `file://` URL that
  `open` treats as a local file or application
- the daemon runs `Command::new("/usr/bin/open").arg(url)` — one `argv` element,
  absolute path, no shell anywhere, so there is nothing to quote or inject into

The daemon re-validates every request rather than trusting the client, since the
tunnel is a trust boundary and the daemon is what launches things.

## Known limitation: ASCII-only URLs

A URL must be pure ASCII on the wire. Browsers hide two normalisations that
`std` cannot do:

| You copy                                      | What must be sent                            |
| --------------------------------------------- | -------------------------------------------- |
| `https://bücher.example/x`                    | `https://xn--bcher-kva.example/x` (Punycode) |
| `https://de.wikipedia.org/wiki/Bahnhofstraße` | `…/Bahnhofstra%C3%9Fe` (percent-encoded)     |
| `https://example.com/my report.pdf`           | `…/my%20report.pdf`                          |

`normalize` **rejects** all three rather than encoding them, with an error
saying so. Two tests pin this so it stays a recorded decision.

This never affects OAuth or auth URLs, which arrive already percent-encoded and
so are ASCII by construction. It only bites on hand-written links.

### Why, and how to lift it

The fix is the [`url`](https://crates.io/crates/url) crate, rejected on cost:
`url` → `idna` → `idna_adapter` → the ICU4X stack, some 20+ crates, and
`idna_adapter` exposes only a `compiled_data` feature so there is no lighter
backend. Zero dependencies also keeps the guest build in the VM boot path
effectively free.

`normalize` returns an owned `String` rather than borrowing specifically so the
swap touches one function body and zero call sites:

```rust
let parsed = Url::parse(input).map_err(..)?;
// check scheme is http/https and a host is present, then:
Ok(parsed.as_str().to_owned())   // guaranteed ASCII
```

The two tests then flip from "rejected" to "percent-encoded".

## Why one crate with two binaries

`tools/README.md` argues against multi-binary crates, and this is a deliberate
exception. That argument is about dependency isolation between **unrelated**
tools. These are two halves of one protocol that must agree byte-for-byte on
validation and framing: separate crates would need a third shared lib crate —
three manifests for one tool — and duplicating the validator would guarantee the
ends eventually drift, which is the bug class this crate exists to avoid.

## Diagnosing a failure

| Where                                | What                                                                                       |
| ------------------------------------ | ------------------------------------------------------------------------------------------ |
| `devbox-open-url --status`           | plist, launchd state, and a live connect to the port                                       |
| `~/Library/Logs/devbox-open-url.log` | every open, rejection and error on the Mac. Timestamps are epoch seconds: `date -r <secs>` |
| `xdg-open <url>` in the VM           | reproduces by hand; prints the reason                                                      |

Client-side rejections short-circuit before the network, so they never reach the
daemon log. Where the message surfaces depends on the caller: lazygit shows it
in an error popup and Claude Code reports it, but `nvim gx` discards it —
Neovim hard-codes `job_opt.stderr = false` when the opener is `xdg-open`, so you
get only `vim.ui.open: command failed (1)`.

If nothing opens and the log is empty, the caller never invoked `xdg-open`. Some
tools check `$DISPLAY` first and give up on a headless box; `$BROWSER` is set to
`xdg-open` in the guest (fish `conf.d/10-env.fish`) to defeat that.

## Development

```sh
cargo test -p devbox-open-url
cargo clippy -p devbox-open-url --all-targets -- -D warnings
cargo fmt -p devbox-open-url
```

Tests cover `normalize` and the wire format with no network or filesystem —
`read_framed_line` is generic over `Read`, so a byte slice stands in for a
socket. The crate compiles on Linux as well as macOS (the macOS-specific parts
are runtime paths, not `cfg` gates), so `cargo test --workspace` stays green
inside the VM.

After changing anything here, reload the Mac side:

```sh
cargo install --path . --bin devbox-open-url --locked --force
devbox-open-url --install
```

`--force` is required: cargo tracks installs in `~/.cargo/.crates2.json` as
`name version (source)` with no content hash, so an edit under a static `0.1.0`
is silently skipped.
