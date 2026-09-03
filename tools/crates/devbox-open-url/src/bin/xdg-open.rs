//! xdg-open — the guest half of the devbox URL opener.
//!
//! Installed into `~/.cargo/bin` inside the devbox VM, where it becomes *the*
//! `xdg-open`: nothing else in that headless Ubuntu image provides one. Every
//! terminal tool that wants to open a link shells out to this name —
//!
//! - lazygit's `os.openLink` default is literally `xdg-open {{link}} >/dev/null`
//! - `nvim` `gx`
//! - `gh browse`, and anything honouring `$BROWSER`
//!
//! — so replacing this one command fixes all of them at once, with no per-tool
//! configuration.
//!
//! It sends the URL to the `devbox-open-url` daemon on the Mac over the SSH
//! reverse tunnel, and the Mac opens it in the default browser.
//!
//! Also installed on the Mac itself as a side effect of
//! `install/darwin/install.sh` building every crate in the workspace. That is
//! harmless and mildly useful: there it reaches the same daemon directly, so
//! `xdg-open` behaves identically on both machines.
//!
//! ## Exit codes
//!
//! Per the workspace convention in `tools/README.md`:
//!
//! - `0` the Mac accepted the URL
//! - `1` an expected negative result: the URL was refused, or the tunnel is not
//!   up
//! - `2` tool failure: wrong arguments, or an I/O error that is not a refused
//!   connection

use std::net::TcpStream;
use std::process::ExitCode;
use std::time::Duration;

use devbox_open_url::{HOST, PORT, Response, normalize, read_framed_line, write_request};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);

const USAGE: &str = "\
xdg-open — open a URL in the macOS browser from inside the devbox VM

USAGE:
    xdg-open <http(s)-url>

Sends the URL to the devbox-open-url daemon on the Mac over the SSH reverse
tunnel. Only http:// and https:// URLs are accepted.
";

fn main() -> ExitCode {
    // `skip(1)` drops argv[0]. Extra arguments are an error rather than being
    // ignored: real xdg-open takes exactly one URL, and silently dropping the
    // rest would hide a caller's bug.
    let args: Vec<String> = std::env::args().skip(1).collect();

    let url = match args.as_slice() {
        [one] if one == "--help" || one == "-h" => {
            print!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        [one] => one,
        [] => {
            eprint!("{USAGE}");
            return ExitCode::from(2);
        }
        _ => {
            eprintln!("xdg-open: expected exactly one URL, got {}\n", args.len());
            eprint!("{USAGE}");
            return ExitCode::from(2);
        }
    };

    // Validate before opening a socket. The daemon checks again — it has to,
    // since the tunnel is a trust boundary — but failing here means an obviously
    // bad URL never leaves the VM and the error arrives instantly.
    let url = match normalize(url) {
        Ok(url) => url,
        Err(rejection) => {
            eprintln!("xdg-open: {rejection}");
            return ExitCode::from(1);
        }
    };

    match send(&url) {
        Ok(Response::Ok) => ExitCode::SUCCESS,
        Ok(Response::Err(reason)) => {
            eprintln!("xdg-open: the Mac refused this URL: {reason}");
            ExitCode::from(1)
        }
        Err(e) => {
            eprintln!("xdg-open: {e}");
            ExitCode::from(e.exit_code())
        }
    }
}

fn send(url: &str) -> Result<Response, SendError> {
    let addr = format!("{HOST}:{PORT}");

    // `to_socket_addrs` on a literal 127.0.0.1 cannot really fail, but
    // `connect_timeout` needs a `SocketAddr` rather than a string, and a
    // timeout matters: without one a half-open tunnel would hang lazygit.
    let sockaddr = addr
        .parse()
        .map_err(|e| SendError::Io(format!("cannot parse {addr}: {e}")))?;

    let stream = TcpStream::connect_timeout(&sockaddr, CONNECT_TIMEOUT)
        .map_err(|e| SendError::classify(&addr, e))?;

    stream
        .set_read_timeout(Some(CONNECT_TIMEOUT))
        .and_then(|()| stream.set_write_timeout(Some(CONNECT_TIMEOUT)))
        .map_err(|e| SendError::Io(format!("cannot set socket timeouts: {e}")))?;

    write_request(&stream, url).map_err(|e| SendError::Io(format!("cannot send the URL: {e}")))?;

    let line = read_framed_line(&stream)
        .map_err(|e| SendError::Io(format!("no answer from the Mac: {e}")))?
        .ok_or_else(|| {
            // The daemon closed without answering. Reported rather than
            // assumed successful: we have no idea whether it opened anything.
            SendError::Io(
                "the Mac closed the connection without answering — check the \
                 daemon log at ~/Library/Logs/devbox-open-url.log"
                    .to_owned(),
            )
        })?;

    Ok(Response::parse(&line))
}

enum SendError {
    /// Nothing is listening on the tunnel's guest end. By far the most likely
    /// failure, and the one worth explaining properly.
    NotConnected(String),
    Io(String),
}

impl SendError {
    fn classify(addr: &str, e: std::io::Error) -> SendError {
        match e.kind() {
            std::io::ErrorKind::ConnectionRefused | std::io::ErrorKind::TimedOut => {
                SendError::NotConnected(addr.to_owned())
            }
            _ => SendError::Io(format!("cannot connect to {addr}: {e}")),
        }
    }

    fn exit_code(&self) -> u8 {
        match self {
            // Expected negative result: the tunnel simply is not up.
            SendError::NotConnected(_) => 1,
            SendError::Io(_) => 2,
        }
    }
}

impl std::fmt::Display for SendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            // Every cause this can have, because the bare "connection refused"
            // that would otherwise appear inside lazygit explains nothing.
            // `\x20` rather than a literal leading space on each line: Rust's
            // `\` line-continuation strips leading whitespace from the next
            // line, which would silently flatten this whole layout.
            SendError::NotConnected(addr) => write!(
                f,
                "nothing is listening on {addr} — the URL was not opened.\n\
                 \n\
                 The reverse tunnel to the Mac is not up. Check, in order:\n\
                 \n\
                 \x20 1. You are inside an `ssh devbox` session. The tunnel\n\
                 \x20    exists only for the lifetime of that connection, so a\n\
                 \x20    `limactl shell devbox` session will never have it.\n\
                 \n\
                 \x20 2. Your ~/.ssh/config devbox block contains:\n\
                 \x20      RemoteForward {HOST}:{PORT} {HOST}:{PORT}\n\
                 \x20    Regenerate it with devbox/scripts/ssh-config.sh\n\
                 \n\
                 \x20 3. The daemon is loaded on the Mac:\n\
                 \x20      devbox-open-url --status",
                HOST = HOST,
                PORT = PORT,
            ),
            SendError::Io(msg) => write!(f, "{msg}"),
        }
    }
}
