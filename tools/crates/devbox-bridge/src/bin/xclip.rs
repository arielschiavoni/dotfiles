//! xclip — the guest half of the devbox clipboard reader.
//!
//! Installed into `~/.cargo/bin` in the VM, where it becomes *the* `xclip`:
//! nothing else in that headless image provides one. Coding agents read images
//! by shelling out to this name, so supplying it makes `Ctrl+V` paste a
//! screenshot taken on the Mac.
//!
//! ```text
//! opencode:     xclip -selection clipboard -t image/png -o
//! Claude Code:  xclip -selection clipboard -t TARGETS   -o   (is there one?)
//!               xclip -selection clipboard -t image/png -o   (give it to me)
//! ```
//!
//! Only those two invocations are supported; anything else exits 2 saying so.
//!
//! Exit codes (`tools/README.md`):
//!   0  image delivered (or `image/png` listed)
//!   1  round trip fine, but the Mac clipboard holds no image
//!   2  tunnel down, I/O failure, or unsupported arguments
//!
//! `devbox/scripts/verify.sh` uses exit 1 to prove the path works without
//! putting a test screenshot on your clipboard.

use std::io::{self, Write};
use std::net::TcpStream;
use std::process::ExitCode;
use std::time::Duration;

use devbox_bridge::{HOST, PORT, Request, Response, tunnel_down};

/// A ceiling, not a target: Claude Code kills clipboard helpers that take too
/// long, and loopback plus SSH on the same machine is instant.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);

const USAGE: &str = "\
xclip — read the Mac clipboard from inside the devbox VM

USAGE:
    xclip -selection clipboard -t TARGETS   -o    list available formats
    xclip -selection clipboard -t image/png -o    write the image to stdout

Talks to the devbox-bridge daemon on the Mac over the SSH reverse tunnel.
Only the two invocations above are supported, which is what opencode and
Claude Code use to paste images.
";

/// The two things a caller can be asking for.
#[derive(Debug, PartialEq, Eq)]
enum Ask {
    Targets,
    Image,
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();

    if args.iter().any(|a| a == "--help" || a == "-h") {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }

    let ask = match parse_args(&args) {
        Ok(ask) => ask,
        Err(reason) => {
            eprintln!("xclip: {reason}\n");
            eprint!("{USAGE}");
            return ExitCode::from(2);
        }
    };

    match ask {
        Ask::Targets => match send(&Request::ClipTypes) {
            // Claude Code greps this list for "image/", so one line is enough.
            Ok(Response::Text(types)) => {
                println!("{types}");
                ExitCode::SUCCESS
            }
            Ok(Response::Empty) => ExitCode::from(1),
            other => fail(other),
        },
        Ask::Image => match send(&Request::ClipImage) {
            Ok(Response::Bytes(png)) => match io::stdout().write_all(&png) {
                Ok(()) => ExitCode::SUCCESS,
                // A closed pipe is the caller giving up, not our failure.
                Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::from(1),
                Err(e) => {
                    eprintln!("xclip: cannot write the image to stdout: {e}");
                    ExitCode::from(2)
                }
            },
            Ok(Response::Empty) => ExitCode::from(1),
            other => fail(other),
        },
    }
}

/// Report anything that is neither a payload nor a plain "nothing there".
fn fail(outcome: Result<Response, SendError>) -> ExitCode {
    match outcome {
        Ok(Response::Err(reason)) => {
            eprintln!("xclip: the Mac could not read its clipboard: {reason}");
            ExitCode::from(2)
        }
        Ok(other) => {
            eprintln!("xclip: unexpected answer from the Mac: {other:?}");
            ExitCode::from(2)
        }
        Err(e) => {
            eprintln!("xclip: {e}");
            ExitCode::from(e.exit_code())
        }
    }
}

/// Parses flags rather than matching the argv string, so flag order and
/// `-t image/jpeg` cannot slip through by accident. `-selection` must be
/// `clipboard`; `primary` is the X11 middle-click selection and must not
/// silently get the clipboard instead.
fn parse_args(args: &[String]) -> Result<Ask, String> {
    let mut selection: Option<&str> = None;
    let mut target: Option<&str> = None;
    let mut out = false;

    let mut i = 0;
    while i < args.len() {
        let arg = args[i].as_str();
        match arg {
            "-selection" | "--selection" => {
                selection = Some(args.get(i + 1).ok_or("-selection needs a value")?);
                i += 2;
            }
            "-t" | "-target" | "--target" => {
                target = Some(args.get(i + 1).ok_or("-t needs a value")?);
                i += 2;
            }
            "-o" | "-out" | "--out" => {
                out = true;
                i += 1;
            }
            other => return Err(format!("unsupported argument {other:?}")),
        }
    }

    if !out {
        return Err("only reading is supported, so -o is required".to_owned());
    }
    match selection {
        Some("clipboard") => {}
        Some(other) => {
            return Err(format!(
                "only -selection clipboard is supported, got {other:?}"
            ));
        }
        None => return Err("-selection clipboard is required".to_owned()),
    }
    match target {
        Some("TARGETS") => Ok(Ask::Targets),
        Some("image/png") => Ok(Ask::Image),
        Some(other) => Err(format!(
            "only -t TARGETS and -t image/png are supported, got {other:?}"
        )),
        None => Err("-t is required".to_owned()),
    }
}

fn send(request: &Request) -> Result<Response, SendError> {
    let addr = format!("{HOST}:{PORT}");

    // `connect_timeout` needs a `SocketAddr`, and the timeout matters: without
    // one a half-open tunnel would hang the agent.
    let sockaddr = addr
        .parse()
        .map_err(|e| SendError::Io(format!("cannot parse {addr}: {e}")))?;

    let stream = TcpStream::connect_timeout(&sockaddr, CONNECT_TIMEOUT)
        .map_err(|e| SendError::classify(&addr, e))?;

    stream
        .set_read_timeout(Some(CONNECT_TIMEOUT))
        .and_then(|()| stream.set_write_timeout(Some(CONNECT_TIMEOUT)))
        .map_err(|e| SendError::Io(format!("cannot set socket timeouts: {e}")))?;

    request
        .write_to(&stream)
        .map_err(|e| SendError::Io(format!("cannot send the request: {e}")))?;

    Response::read_from(&stream)
        .map_err(|e| SendError::Io(format!("no answer from the Mac: {e}")))?
        .ok_or_else(|| {
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

    /// Always 2. Unlike the "no image" case, the caller must be able to tell
    /// an empty clipboard from a broken bridge.
    fn exit_code(&self) -> u8 {
        2
    }
}

impl std::fmt::Display for SendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SendError::NotConnected(addr) => write!(f, "{}", tunnel_down(addr)),
            SendError::Io(msg) => write!(f, "{msg}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| (*s).to_owned()).collect()
    }

    /// What Claude Code runs to ask "is there an image?".
    #[test]
    fn accepts_claude_targets_probe() {
        let a = args(&["-selection", "clipboard", "-t", "TARGETS", "-o"]);
        assert_eq!(parse_args(&a).unwrap(), Ask::Targets);
    }

    /// What both opencode and Claude Code run to fetch the image.
    #[test]
    fn accepts_image_read() {
        let a = args(&["-selection", "clipboard", "-t", "image/png", "-o"]);
        assert_eq!(parse_args(&a).unwrap(), Ask::Image);
    }

    /// Flags are parsed, not pattern-matched.
    #[test]
    fn flag_order_does_not_matter() {
        let a = args(&["-o", "-t", "image/png", "-selection", "clipboard"]);
        assert_eq!(parse_args(&a).unwrap(), Ask::Image);
    }

    /// The primary selection is middle-click paste, a different thing.
    #[test]
    fn refuses_primary_selection() {
        let a = args(&["-selection", "primary", "-t", "image/png", "-o"]);
        assert!(parse_args(&a).is_err());
    }

    /// Claude Code's third fallback: refused, not answered with PNG.
    #[test]
    fn refuses_other_image_types() {
        let a = args(&["-selection", "clipboard", "-t", "image/bmp", "-o"]);
        assert!(parse_args(&a).is_err());
    }

    /// Without `-o` this is a write, which is not supported.
    #[test]
    fn refuses_writes() {
        let a = args(&["-selection", "clipboard"]);
        assert!(parse_args(&a).is_err());
    }

    #[test]
    fn refuses_empty_and_unknown_args() {
        assert!(parse_args(&[]).is_err());
        assert!(parse_args(&args(&["-rmlastnl"])).is_err());
    }

    #[test]
    fn refuses_flags_missing_their_value() {
        assert!(parse_args(&args(&["-selection"])).is_err());
        assert!(parse_args(&args(&["-selection", "clipboard", "-t"])).is_err());
    }
}
