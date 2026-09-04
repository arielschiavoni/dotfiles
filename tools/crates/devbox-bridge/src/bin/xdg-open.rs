//! xdg-open — the guest half of the devbox URL opener.
//!
//! Installed into `~/.cargo/bin` in the VM, where it becomes *the* `xdg-open`:
//! nothing else in that headless image provides one. lazygit (`os.openLink`
//! defaults to `xdg-open {{link}} >/dev/null`), `nvim gx`, `gh browse` and
//! anything honouring `$BROWSER` shell out to this name, so supplying it fixes
//! all of them with no per-tool configuration.
//!
//! Sends the URL to the `devbox-bridge` daemon on the Mac over the SSH reverse
//! tunnel. Also installed on the Mac by `install/darwin/install.sh`, where it
//! reaches the same daemon directly and behaves identically.
//!
//! Exit codes (`tools/README.md`): 0 accepted, 1 refused or tunnel down,
//! 2 bad arguments or I/O failure.

use std::net::TcpStream;
use std::process::ExitCode;
use std::time::Duration;

use devbox_bridge::{HOST, PORT, Request, Response, normalize, tunnel_down};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);

const USAGE: &str = "\
xdg-open — open a URL in the macOS browser from inside the devbox VM

USAGE:
    xdg-open <http(s)-url>

Sends the URL to the devbox-bridge daemon on the Mac over the SSH reverse
tunnel. Only http:// and https:// URLs are accepted.
";

fn main() -> ExitCode {
    // Extra arguments are an error: real xdg-open takes one URL, and dropping
    // the rest would hide a caller's bug.
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

    // Validated before opening a socket, so a bad URL never leaves the VM.
    // The daemon checks again regardless.
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
        // A clipboard answer to an OPEN request can only be a bug.
        Ok(other) => {
            eprintln!("xdg-open: unexpected answer from the Mac: {other:?}");
            ExitCode::from(2)
        }
        Err(e) => {
            eprintln!("xdg-open: {e}");
            ExitCode::from(e.exit_code())
        }
    }
}

fn send(url: &str) -> Result<Response, SendError> {
    let addr = format!("{HOST}:{PORT}");

    // The timeout matters: without one a half-open tunnel hangs lazygit.
    let sockaddr = addr
        .parse()
        .map_err(|e| SendError::Io(format!("cannot parse {addr}: {e}")))?;

    let stream = TcpStream::connect_timeout(&sockaddr, CONNECT_TIMEOUT)
        .map_err(|e| SendError::classify(&addr, e))?;

    stream
        .set_read_timeout(Some(CONNECT_TIMEOUT))
        .and_then(|()| stream.set_write_timeout(Some(CONNECT_TIMEOUT)))
        .map_err(|e| SendError::Io(format!("cannot set socket timeouts: {e}")))?;

    Request::Open(url.to_owned())
        .write_to(&stream)
        .map_err(|e| SendError::Io(format!("cannot send the URL: {e}")))?;

    Response::read_from(&stream)
        .map_err(|e| SendError::Io(format!("no answer from the Mac: {e}")))?
        .ok_or_else(|| {
            // Reported, not assumed successful: we cannot tell whether it
            // opened anything.
            SendError::Io(
                "the Mac closed the connection without answering — check the \
                 daemon log at ~/Library/Logs/devbox-bridge.log"
                    .to_owned(),
            )
        })
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
            // A bare "connection refused" inside lazygit explains nothing.
            SendError::NotConnected(addr) => write!(f, "{}", tunnel_down(addr)),
            SendError::Io(msg) => write!(f, "{msg}"),
        }
    }
}
