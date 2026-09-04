# devbox-bridge

Lets the [devbox VM](../../../devbox/) reach the Mac. Two capabilities, one
daemon, one SSH tunnel:

| Guest command | Does | Fixes |
| ------------- | ---- | ----- |
| `xdg-open`    | opens a URL in the macOS browser | lazygit `o`, `nvim gx`, `gh browse` |
| `xclip`       | reads the Mac clipboard as PNG   | `Ctrl+V` image paste in opencode and Claude Code |

The guest is headless and provides neither command. Supplying the two names is
the whole trick — no per-tool configuration anywhere.

## How it works

```
guest (Ubuntu)                          │  mac (darwin)
lazygit `o` → xdg-open <url>            │
opencode Ctrl+V → xclip -t image/png -o │
      └─ TcpStream 127.0.0.1:17325      │
              └──── sshd RemoteForward ─┼───── devbox-bridge (LaunchAgent)
                                        │        → /usr/bin/open <url>
                                        │        → pngpaste - (clipboard)
```

Both ends bind loopback only. The `RemoteForward` in the devbox
`~/.ssh/config` block lives only for the duration of an `ssh devbox` session,
so a `limactl shell devbox` session has no tunnel and the clients say so.

## Wire format

One request per connection, newline-framed. Only `OK-BYTES` has a body, and its
length is declared up front so the reader never looks for a delimiter inside
binary data:

```
-> OPEN https://github.com/owner/repo/pull/42
<- OK

-> CLIP-TYPES
<- OK-TEXT image/png            (or OK-NONE when no image is copied)

-> CLIP-IMAGE
<- OK-BYTES 40213
   <40213 bytes of PNG>         (or OK-NONE)

<- ERR <reason>                 (any request)
```

## Clipboard

Two `xclip` invocations are supported, because two are used:

```sh
xclip -selection clipboard -t TARGETS   -o    # prints "image/png", or nothing
xclip -selection clipboard -t image/png -o    # writes the PNG to stdout
```

opencode runs the second; Claude Code runs the first to check and the second
to fetch. Anything else — `-selection primary`, `-t image/bmp`, a write — exits
2 saying so, since there is no real `xclip` to fall back to and a silent no-op
would hide the caller's bug.

Exit codes, per `tools/README.md`:

| Code | Meaning |
| ---- | ------- |
| 0    | image delivered |
| 1    | round trip fine, no image on the Mac clipboard |
| 2    | tunnel down, I/O failure, or unsupported arguments |

Both agents treat any non-zero as "no image", so the 1/2 split is for humans
and for `devbox/scripts/verify.sh`, whose liveness probe needs nothing on your
clipboard.

`CLIP-TYPES` answers by fetching the image rather than with a cheaper probe:
reporting `image/png` and then serving nothing makes an agent post an empty
image to its API and error out for the rest of the session.

The Mac reads the clipboard with `pngpaste -`, which turns TIFF, PDF or PNG on
the pasteboard into PNG. Its **absolute** path matters: launchd gives the
daemon a bare `PATH` without `/opt/homebrew/bin`, so a plain `pngpaste` never
resolves and every paste looks like an empty clipboard.
`devbox-bridge --status` reports whether it was found.

## Binaries

| Binary          | Machine    | Installed by                                                          |
| --------------- | ---------- | --------------------------------------------------------------------- |
| `devbox-bridge` | macOS host | `devbox/scripts/create.sh`; `install/darwin/install.sh` on a fresh Mac |
| `xdg-open`      | guest VM   | `devbox/provision/20-user.sh`, on every boot                          |
| `xclip`         | guest VM   | same, behind `--features guest`                                       |

```sh
devbox-bridge             # run the daemon (what launchd invokes)
devbox-bridge --install   # write the launchd plist and (re)load it
devbox-bridge --status    # loaded? listening? pngpaste found?
```

`xclip` sits behind the `guest` feature so `install/darwin/install.sh`, which
builds every crate with default features, cannot put a fake `xclip` in
`~/.cargo/bin` on the Mac — Cargo skips a target whose required features are
off, so that script needs no special case.

`--install` lives in the binary because the plist needs an absolute path to the
program and `std::env::current_exe` knows it. Lima provisioning cannot do it:
that runs inside the guest, with no `launchctl` for the Mac.

All three share one crate against the advice in `tools/README.md` because they
are halves of one protocol: split up, they would drift on validation and
framing.

## Security properties

Any process in the VM can, while an SSH session is live:

- make the Mac open an `http`/`https` URL
- read the Mac clipboard

Both are intended. Stated plainly: whatever you have copied, a password
included, is readable by anything in the guest while `ssh devbox` is connected.
That is acceptable because the VM is local, single-user and yours — which is
also why there is no token or nonce anywhere in this crate.

Within that boundary:

- `normalize` requires an `http://` or `https://` prefix, so the URL cannot be a
  leading `-` that `open` reads as a flag, nor a bare path or `file://` URL that
  `open` treats as a local file or application
- the daemon runs `Command::new("/usr/bin/open").arg(url)` — one `argv` element,
  absolute path, no shell, so there is nothing to quote or inject into
- the clipboard is read, never written, and only as PNG
- declared body lengths are checked against `MAX_IMAGE` (32 MiB) *before*
  allocating, on both ends

The daemon re-validates every request rather than trusting the client: the
tunnel is a trust boundary, and the daemon is what launches things.

## Known limitation: ASCII-only URLs

A URL must be pure ASCII on the wire, and `normalize` rejects rather than
encodes the three cases browsers hide:

| You copy                                      | What must be sent                            |
| --------------------------------------------- | -------------------------------------------- |
| `https://bücher.example/x`                    | `https://xn--bcher-kva.example/x` (Punycode) |
| `https://de.wikipedia.org/wiki/Bahnhofstraße` | `…/Bahnhofstra%C3%9Fe` (percent-encoded)     |
| `https://example.com/my report.pdf`           | `…/my%20report.pdf`                          |

Auth and OAuth URLs arrive percent-encoded and so are ASCII already; this only
bites on hand-written links.

The fix is the [`url`](https://crates.io/crates/url) crate, rejected on cost:
20+ crates via `idna` → ICU4X, whose `idna_adapter` offers only a
`compiled_data` feature. `normalize` returns an owned `String`, so adopting it
would touch that one function body and no call sites.

## Not implemented

- **Writing the clipboard** (a remote yank landing on the Mac). tmux and neovim
  already do text via OSC 52, which needs no daemon.
- **Codex CLI image paste.** Codex reads X11 in-process via `arboard` rather
  than shelling out, so supplying a command name cannot intercept it; that
  needs Xvfb plus an X11 selection owner.

## Diagnosing a failure

| Where                             | What                                                                                       |
| --------------------------------- | ------------------------------------------------------------------------------------------ |
| `devbox-bridge --status`          | plist, launchd state, a live connect to the port, and whether pngpaste resolves            |
| `~/Library/Logs/devbox-bridge.log`| every open, clipboard read, rejection and error. Timestamps are epoch seconds: `date -r <secs>` |
| `xdg-open <url>` in the VM        | reproduces by hand; prints the reason                                                      |
| `xclip -selection clipboard -t TARGETS -o; echo $status` in the VM | `1` = tunnel fine but nothing copied, `2` = bridge broken |

Client-side rejections short-circuit before the network, so they never reach
the daemon log, and where the message surfaces depends on the caller. lazygit
shows it in a popup; `nvim gx` discards it, because Neovim hard-codes
`job_opt.stderr = false` for `xdg-open` and leaves you with
`vim.ui.open: command failed (1)`. The agents discard `xclip` stderr entirely
and report no image, so run it by hand to see why.

If nothing opens and the log is empty, the caller never invoked `xdg-open`.
Some tools check `$DISPLAY` first and give up on a headless box, so `$BROWSER`
is set to `xdg-open` in the guest (fish `conf.d/10-env.fish`). Image paste
needs no `$DISPLAY`: both agents pick their Linux clipboard commands by
platform alone.

## Development

```sh
cargo test -p devbox-bridge --all-features
cargo clippy -p devbox-bridge --all-targets --all-features -- -D warnings
cargo fmt -p devbox-bridge
```

`--all-features` or the `xclip` binary is skipped and never linted.

Tests cover `normalize`, argument parsing and the wire format with no network
or filesystem: the framing helpers are generic over `Read`/`Write`, so a byte
slice stands in for a socket. The macOS-specific parts are runtime paths rather
than `cfg` gates, so the crate also compiles in the VM and
`cargo test --workspace` stays green there.

Reload the Mac side:

```sh
cargo install --path . --bin devbox-bridge --locked --force
devbox-bridge --install
```

In the guest, re-run `devbox/provision/20-user.sh` or:

```sh
cargo install --path . --bin xdg-open --bin xclip --features guest --locked --force
```
