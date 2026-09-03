//! xdg-open — the guest half of the devbox URL opener.
//!
//! Installed into `~/.cargo/bin` in the VM, where it becomes *the* `xdg-open`:
//! nothing else in that headless image provides one. lazygit (`os.openLink`
//! defaults to `xdg-open {{link}} >/dev/null`), `nvim gx`, `gh browse` and
//! anything honouring `$BROWSER` all shell out to this name, so replacing it
//! fixes all of them with no per-tool configuration.
//!
//! Sends the URL to the `devbox-open-url` daemon on the Mac over the SSH
//! reverse tunnel. Also installed on the Mac by `install/darwin/install.sh`,
//! where it reaches the same daemon directly and behaves identically.
//!
//! Exit codes (`tools/README.md`): 0 accepted, 1 refused or tunnel down,
//! 2 bad arguments or I/O failure.

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
    // Extra arguments are an error, not ignored: real xdg-open takes one URL
    // and silently dropping the rest would hide a caller's bug.
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

    // Validate before opening a socket, so a bad URL never leaves the VM and
    // the error is instant. The daemon checks again regardless.
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

    // `connect_timeout` needs a `SocketAddr`, and the timeout matters: without
    // one a half-open tunnel would hang lazygit.
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
            // Reported, not assumed successful: we cannot tell whether it
            // opened anything.
            SendError::Io(
                "the Mac closed the connection without answering — check the \
                 daemon log at ~/Library/Logs/devbox-open-url.log"
                    .to_owned(),
            )
        })?;

    Ok(Response::parse(&line))
}

enum SendError {
    /// Nothing listening on the tunnel's guest end — the likeliest failure.
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
            // Expected negative result: the tunnel is not up.
            SendError::NotConnected(_) => 1,
            SendError::Io(_) => 2,
        }
    }
}

impl std::fmt::Display for SendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            // All three causes: a bare "connection refused" inside lazygit
            // explains nothing.
            // `\x20` because Rust's `\` line-continuation strips leading
            // whitespace, which would flatten this layout.
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
