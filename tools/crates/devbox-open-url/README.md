# devbox-open-url

Open URLs from the [devbox VM](../../../devbox/) in the macOS default browser.

The guest is a headless Ubuntu image, so nothing there provides `xdg-open` —
which is what every terminal tool shells out to when it wants to open a link.
lazygit's `os.openLink` default is literally `xdg-open {{link}} >/dev/null`, so
pressing `o` on a pull request in the VM used to produce:

```
fish: Unknown command: xdg-open
```

This crate ships two binaries: a replacement `xdg-open` for the guest, and a
daemon for the Mac that receives URLs and calls `/usr/bin/open`. Replacing that
one command name fixes lazygit, `nvim gx`, `gh browse` and anything honouring
`$BROWSER` at once, with no per-tool configuration — in particular, **no lazygit
config change**: `os.openLink` stays empty and its Linux default now resolves.

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

Both ends bind loopback only. Nothing is exposed to any network: the guest
reaches the Mac exclusively through the `RemoteForward` in the devbox
`~/.ssh/config` block, which exists only for the lifetime of an `ssh devbox`
session. A `limactl shell devbox` session therefore has no tunnel — by design,
and the client says so when it cannot connect.

The wire format is one newline-terminated line each way:

```
-> https://github.com/owner/repo/pull/42\n
<- OK\n                        (or)  ERR <reason>\n
```

## Binaries

| Binary            | Machine    | Installed by                                                               |
| ----------------- | ---------- | -------------------------------------------------------------------------- |
| `devbox-open-url` | macOS host | `devbox/scripts/create.sh`, and `install/darwin/install.sh` on a fresh Mac |
| `xdg-open`        | guest VM   | `devbox/provision/20-user.sh`, on every boot                               |

```sh
devbox-open-url             # run the daemon (what launchd invokes)
devbox-open-url --install   # write the launchd plist and (re)load it
devbox-open-url --status    # installed? loaded? listening?
xdg-open <http(s)-url>      # send one URL to the Mac
```

`--install` lives in the binary rather than in a shell script because the plist
must name an absolute path to the program, and
[`std::env::current_exe`](https://doc.rust-lang.org/std/env/fn.current_exe.html)
simply knows it. A shell installer would have to reconstruct that path and
expand `$HOME` into an XML file that cannot expand it itself — so this removes a
script, a plist template, and the class of bug where the loaded agent points at
a stale binary.

This setup cannot run from Lima provisioning, which is the intuitive place to
put it. Those scripts execute _inside the guest_, which has no access to
`launchctl` on the Mac — and granting the guest that access is precisely what
this tool exists to do, in one narrow direction. Host-side setup therefore lives
in `devbox/scripts/create.sh`.

## Security properties

Any process in the VM can make the Mac open an `http`/`https` URL while an SSH
session is live. That is the intended capability. It is bounded to _exactly_
that by two things in `normalize`:

- the URL must start with `http://` or `https://`, so it cannot be a leading
  `-` that `open` would read as a flag, and cannot be a bare path or a
  `file://` URL that `open` would treat as a local file or application
- the daemon invokes `Command::new("/usr/bin/open").arg(url)` — one `argv`
  element, absolute path, **no shell anywhere in the path**, so there is nothing
  to quote, escape, or inject into

The daemon re-validates every request rather than trusting the client, because
the tunnel is a trust boundary and the daemon is the side that launches things.

## Known limitation: ASCII-only URLs

A URL must be pure ASCII on the wire. Browsers hide two normalisations that
`std` cannot do:

| You copy                                      | What must be sent                                  |
| --------------------------------------------- | -------------------------------------------------- |
| `https://bücher.example/x`                    | `https://xn--bcher-kva.example/x` (Punycode, IDNA) |
| `https://de.wikipedia.org/wiki/Bahnhofstraße` | `…/wiki/Bahnhofstra%C3%9Fe` (percent-encoded)      |
| `https://example.com/my report.pdf`           | `…/my%20report.pdf`                                |

`normalize` **rejects** all three rather than encoding them, with an error that
says so and suggests percent-encoding. Two tests
(`rejects_non_ascii_path_for_now`, `rejects_idn_host_for_now`) pin this
behaviour so it is a recorded decision rather than an accident.

### Why, and how to lift it

The fix is the [`url`](https://crates.io/crates/url) crate, which does both
normalisations. It was rejected on cost: `url` → `idna` → `idna_adapter` → the
ICU4X stack (`icu_normalizer`, `icu_properties`, `icu_collections`,
`icu_provider`, `zerovec`, `zerotrie`, `yoke`, `zerofrom`, `litemap`, `tinystr`,
`writeable`, `displaydoc` and the compiled Unicode data crates) — **20+ crates**
for an edge case that has not yet occurred in practice. `idna_adapter` exposes
only a `compiled_data` feature, so there is no lighter backend to opt into.
Zero dependencies also keeps the guest-side build in the VM boot path
effectively free.

If it does become a real problem, the upgrade is deliberately cheap. `normalize`
returns an owned `String` rather than borrowing its input _specifically_ so that
this swap touches one function body and zero call sites:

```rust
let parsed = Url::parse(input).map_err(..)?;
// check scheme is http/https and a host is present, then:
Ok(parsed.as_str().to_owned())   // guaranteed ASCII
```

The two tests above then flip from "rejected" to "percent-encoded", which is how
you know the upgrade landed.

## Why one crate with two binaries

`tools/README.md` argues against multi-binary crates, and this crate is a
deliberate exception. That argument is about **dependency isolation between
unrelated tools**: one tool pulling a heavy dependency should not slow down
builds of the others, and two tools may need different major versions of the
same crate.

Neither applies here. These are two halves of one protocol that must agree
byte-for-byte on URL validation and framing. Splitting them into separate crates
would need a third shared library crate — three manifests to express one tool —
and duplicating the validator instead would guarantee the two ends eventually
drift, which is the exact bug class this crate exists to avoid.

## Development

```sh
cargo test -p devbox-open-url                                  # 29 tests
cargo clippy -p devbox-open-url --all-targets -- -D warnings
cargo fmt -p devbox-open-url
```

The tests cover `normalize` and the wire format directly, with no network or
filesystem involved: `read_framed_line` is generic over `Read`, so a byte slice
stands in for a socket.

The crate compiles on Linux as well as macOS — the macOS-specific parts
(`/usr/bin/open`, `launchctl`) are runtime paths, not `cfg` gates — so
`cargo test --workspace` stays green inside the VM.

After changing anything here, reload the Mac side with:

```sh
cargo install --path . --bin devbox-open-url --locked --force
devbox-open-url --install
```

`--force` is required. Cargo tracks installs in `~/.cargo/.crates2.json` as
`name version (source)` with no content hash, so an edit under a static
`0.1.0` is otherwise silently skipped and you keep running the old binary.
