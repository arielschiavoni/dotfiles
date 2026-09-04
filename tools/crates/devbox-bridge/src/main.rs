//! devbox-bridge — the macOS half of the devbox guest-to-host bridge.
//!
//! A launchd user agent on `127.0.0.1:17325` that opens URLs in the browser
//! and serves the clipboard as PNG. The guest reaches it through the SSH
//! reverse tunnel in `devbox/scripts/ssh-config.sh`.
//!
//! ```text
//! devbox-bridge             run the daemon (what launchd invokes)
//! devbox-bridge --install   write the launchd plist and load it
//! devbox-bridge --status    loaded, listening, clipboard readable?
//! ```
//!
//! `--install` lives here because the plist needs an absolute path to the
//! program and [`std::env::current_exe`] knows it. It cannot run from Lima
//! provisioning, which executes inside the guest with no `launchctl` here;
//! `devbox/scripts/create.sh` drives host-side setup.
//!
//! Exit codes follow `tools/README.md`: 0 success, 1 expected negative, 2 tool
//! failure.

use std::fmt::Write as _;
use std::fs;
use std::net::{TcpListener, TcpStream};
use std::os::unix::fs::MetadataExt as _;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use devbox_bridge::{HOST, MAX_IMAGE, PORT, Request, Response, normalize, read_framed_line};

/// `com.ariel.` matches the other hand-written agents in `~/Library/LaunchAgents`.
const LABEL: &str = "com.ariel.devbox-bridge";

/// Absolute, not a `PATH` lookup: launchd hands us an environment we do not
/// control.
const OPEN_BIN: &str = "/usr/bin/open";

/// `pngpaste` turns whatever the pasteboard holds — TIFF, PDF, PNG — into PNG
/// on stdout. Declared in `install/darwin/Brewfile`.
///
/// Absolute paths: launchd gives the daemon a bare `PATH` without
/// `/opt/homebrew/bin`, so a plain `pngpaste` never resolves and every paste
/// looks like an empty clipboard.
const PNGPASTE_CANDIDATES: &[&str] = &["/opt/homebrew/bin/pngpaste", "/usr/local/bin/pngpaste"];

/// The accept loop is serial, so a stalled guest must not wedge it. A few MB
/// of PNG over loopback is far inside this.
const IO_TIMEOUT: Duration = Duration::from_secs(5);

const USAGE: &str = "\
devbox-bridge — serve URLs and the clipboard to the devbox VM

USAGE:
    devbox-bridge              run the daemon in the foreground
    devbox-bridge --install    write the launchd plist and (re)load it
    devbox-bridge --status     report installed / loaded / listening / pngpaste
    devbox-bridge --help

The daemon listens on 127.0.0.1:17325 and answers three requests:
  OPEN <url>    hand an http(s) URL to `open`
  CLIP-TYPES    report whether the clipboard holds an image
  CLIP-IMAGE    send the clipboard as PNG

The guest reaches it via `RemoteForward` in the devbox ~/.ssh/config block.
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();

    match args.first().map(String::as_str) {
        None => run_daemon(),
        Some("--install") => report(install()),
        Some("--status") => status(),
        Some("--help" | "-h") => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        Some(other) => {
            eprintln!("devbox-bridge: unknown argument {other:?}\n");
            eprint!("{USAGE}");
            ExitCode::from(2)
        }
    }
}

/// Print the outcome and map it to an exit code.
fn report(outcome: Result<String, String>) -> ExitCode {
    match outcome {
        Ok(msg) => {
            println!("{msg}");
            ExitCode::SUCCESS
        }
        Err(msg) => {
            eprintln!("devbox-bridge: {msg}");
            ExitCode::from(2)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Daemon
// ─────────────────────────────────────────────────────────────────────────────

fn run_daemon() -> ExitCode {
    let listener = match TcpListener::bind((HOST, PORT)) {
        Ok(l) => l,
        Err(e) => {
            // A bind clash is otherwise silent, and launchd keeps restarting us.
            log(&format!(
                "FATAL: cannot bind {HOST}:{PORT}: {e}. Another process is \
                 probably already listening (`lsof -nP -iTCP:{PORT}`)."
            ));
            return ExitCode::from(2);
        }
    };

    log(&format!("listening on {HOST}:{PORT}"));

    // Serial: `open` and `pngpaste` return in milliseconds for one user, so a
    // thread per connection would add an unbounded-growth failure mode for no
    // throughput.
    for incoming in listener.incoming() {
        match incoming {
            Ok(stream) => handle(stream),
            // Not worth exiting over; the next accept will probably work.
            Err(e) => log(&format!("accept failed: {e}")),
        }
    }

    ExitCode::SUCCESS
}

fn handle(stream: TcpStream) {
    if let Err(e) = stream
        .set_read_timeout(Some(IO_TIMEOUT))
        .and_then(|()| stream.set_write_timeout(Some(IO_TIMEOUT)))
    {
        log(&format!("could not set socket timeouts: {e}"));
        return;
    }

    let line = match read_framed_line(&stream) {
        Ok(Some(line)) => line,
        // Liveness probe from `--status`; logging it would look like failure.
        Ok(None) => return,
        Err(e) => {
            log(&format!("read failed: {e}"));
            // Best effort — the peer may already be gone.
            let _ = respond(&stream, &Response::Err(format!("read failed: {e}")));
            return;
        }
    };

    let response = match Request::parse(&line) {
        Err(reason) => {
            log(&format!("rejected {line:?}: {reason}"));
            Response::Err(reason)
        }
        Ok(Request::Open(url)) => open_request(&url),
        Ok(Request::ClipTypes) => clip_types(),
        Ok(Request::ClipImage) => clip_image(),
    };

    if let Err(e) = respond(&stream, &response) {
        log(&format!("could not write response: {e}"));
    }
}

fn respond(stream: &TcpStream, response: &Response) -> std::io::Result<()> {
    response.write_to(stream)
}

/// Re-validated here: the client checks too, but the tunnel is a trust
/// boundary and this is the side that launches something.
fn open_request(url: &str) -> Response {
    match normalize(url) {
        Err(rejection) => {
            log(&format!("rejected {url:?}: {rejection}"));
            Response::Err(rejection.to_string())
        }
        Ok(url) => match open_url(&url) {
            Ok(()) => {
                log(&format!("opened {url}"));
                Response::Ok
            }
            Err(e) => {
                log(&format!("failed to open {url}: {e}"));
                Response::Err(e)
            }
        },
    }
}

/// One `argv` element, no shell, nothing to escape. With `normalize`
/// guaranteeing an `http(s)://` prefix, `open` cannot be steered into treating
/// it as a flag, a file, or an application.
fn open_url(url: &str) -> Result<(), String> {
    let status = Command::new(OPEN_BIN)
        .arg(url)
        .status()
        .map_err(|e| format!("could not run {OPEN_BIN}: {e}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!("{OPEN_BIN} exited with {status}"))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Clipboard
// ─────────────────────────────────────────────────────────────────────────────

/// Answers "is there an image?" with the same read as [`clip_image`], so the
/// two cannot disagree. A cheaper probe that reports `image/png` and then
/// serves nothing makes an agent post an empty image to its API.
fn clip_types() -> Response {
    match read_clipboard_png() {
        Ok(Some(_)) => Response::Text("image/png".to_owned()),
        Ok(None) => Response::Empty,
        Err(e) => {
            log(&format!("clipboard probe failed: {e}"));
            Response::Err(e)
        }
    }
}

fn clip_image() -> Response {
    match read_clipboard_png() {
        Ok(Some(png)) => {
            log(&format!("served {} bytes of PNG", png.len()));
            Response::Bytes(png)
        }
        Ok(None) => Response::Empty,
        Err(e) => {
            log(&format!("clipboard read failed: {e}"));
            Response::Err(e)
        }
    }
}

/// The clipboard as PNG, or `Ok(None)` when it holds no image.
///
/// `pngpaste` exits non-zero with empty stdout when the pasteboard has no
/// image — an ordinary outcome, not a failure. Only a missing binary or an
/// oversized image is an error.
fn read_clipboard_png() -> Result<Option<Vec<u8>>, String> {
    let bin = pngpaste_path().ok_or_else(|| {
        format!(
            "pngpaste not found in {}. Install it with `brew install pngpaste` \
             (it is declared in install/darwin/Brewfile).",
            PNGPASTE_CANDIDATES.join(", ")
        )
    })?;

    // `-` means "write the PNG to stdout".
    let out = Command::new(&bin)
        .arg("-")
        .stderr(Stdio::null())
        .output()
        .map_err(|e| format!("could not run {bin}: {e}"))?;

    if !out.status.success() || out.stdout.is_empty() {
        return Ok(None);
    }

    // Bounded here as well as in the client.
    if out.stdout.len() > MAX_IMAGE {
        return Err(format!(
            "clipboard image is {} bytes, limit is {MAX_IMAGE}",
            out.stdout.len()
        ));
    }

    Ok(Some(out.stdout))
}

fn pngpaste_path() -> Option<String> {
    PNGPASTE_CANDIDATES
        .iter()
        .find(|p| Path::new(p).is_file())
        .map(|p| (*p).to_owned())
}

/// Timestamped line to stderr; launchd captures it into the plist's log file.
/// Epoch seconds because this crate has no dependencies — `date -r <secs>`.
fn log(msg: &str) {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    eprintln!("[{secs}] {msg}");
}

// ─────────────────────────────────────────────────────────────────────────────
// Install / status
// ─────────────────────────────────────────────────────────────────────────────

fn home() -> Result<PathBuf, String> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is not set".to_owned())
}

fn plist_path(home: &Path) -> PathBuf {
    home.join("Library/LaunchAgents")
        .join(format!("{LABEL}.plist"))
}

fn log_path(home: &Path) -> PathBuf {
    home.join("Library/Logs/devbox-bridge.log")
}

/// The launchd domain, e.g. `gui/501`. The uid comes from the owner of `$HOME`
/// because std does not expose `getuid()`.
fn gui_domain(home: &Path) -> Result<String, String> {
    let uid = fs::metadata(home)
        .map_err(|e| format!("cannot stat {}: {e}", home.display()))?
        .uid();
    Ok(format!("gui/{uid}"))
}

/// `launchctl bootout`, ignoring failure: with nothing loaded launchctl says
/// "Boot-out failed: 3: No such process", which is expected here.
fn bootout(domain: &str, label: &str) {
    let _ = Command::new("/bin/launchctl")
        .args(["bootout", &format!("{domain}/{label}")])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn install() -> Result<String, String> {
    if !cfg!(target_os = "macos") {
        return Err(
            "--install only works on macOS; the daemon belongs on the host, not \
             in the guest"
                .to_owned(),
        );
    }

    let home = home()?;
    let exe = std::env::current_exe()
        .map_err(|e| format!("cannot determine my own path: {e}"))?
        .canonicalize()
        .map_err(|e| format!("cannot canonicalise my own path: {e}"))?;

    let plist = plist_path(&home);
    let logfile = log_path(&home);
    let domain = gui_domain(&home)?;

    for dir in [plist.parent(), logfile.parent()].into_iter().flatten() {
        fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    }

    fs::write(&plist, plist_body(&exe, &logfile))
        .map_err(|e| format!("cannot write {}: {e}", plist.display()))?;

    // Unload first, so --install doubles as "reload after rebuilding".
    bootout(&domain, LABEL);

    let status = Command::new("/bin/launchctl")
        .args(["bootstrap", &domain])
        .arg(&plist)
        .status()
        .map_err(|e| format!("cannot run launchctl: {e}"))?;

    if !status.success() {
        return Err(format!(
            "launchctl bootstrap {domain} {} failed with {status}",
            plist.display()
        ));
    }

    let mut msg = format!(
        "installed and loaded {LABEL}\n  program: {}\n  plist:   {}\n  log:     {}",
        exe.display(),
        plist.display(),
        logfile.display()
    );
    if pngpaste_path().is_none() {
        let _ = write!(
            msg,
            "\n\nWARNING: pngpaste not found — URLs will work but clipboard \
             images will not.\n         Fix with: brew install pngpaste"
        );
    }
    Ok(msg)
}

fn status() -> ExitCode {
    let home = match home() {
        Ok(h) => h,
        Err(e) => {
            eprintln!("devbox-bridge: {e}");
            return ExitCode::from(2);
        }
    };

    let plist = plist_path(&home);
    let mut healthy = true;

    if plist.is_file() {
        println!("plist      OK        {}", plist.display());
    } else {
        println!(
            "plist      MISSING   {}  (run: devbox-bridge --install)",
            plist.display()
        );
        healthy = false;
    }

    match gui_domain(&home).map(|domain| {
        Command::new("/bin/launchctl")
            .args(["print", &format!("{domain}/{LABEL}")])
            .output()
    }) {
        Ok(Ok(out)) if out.status.success() => println!("launchd    OK        {LABEL} is loaded"),
        _ => {
            println!("launchd    MISSING   {LABEL} is not loaded  (run: devbox-bridge --install)");
            healthy = false;
        }
    }

    // The only check that proves it works, and it is the host end of the
    // tunnel, not the guest end.
    let addr = format!("{HOST}:{PORT}");
    match TcpStream::connect(&addr) {
        Ok(_) => println!("listening  OK        {addr}"),
        Err(e) => {
            println!("listening  FAILED    {addr}: {e}");
            healthy = false;
        }
    }

    // Separate line: without pngpaste, URLs still open.
    match pngpaste_path() {
        Some(bin) => println!("pngpaste   OK        {bin}"),
        None => {
            println!("pngpaste   MISSING   clipboard images unavailable  (brew install pngpaste)");
            healthy = false;
        }
    }

    if healthy {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}

/// `KeepAlive` restarts the daemon if it dies; `ThrottleInterval` keeps that
/// from becoming a hot loop when the failure is permanent, such as a bound
/// port.
fn plist_body(exe: &Path, logfile: &Path) -> String {
    let mut s = String::new();
    // `write!` into a String cannot fail.
    let _ = write!(
        s,
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{exe}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>{log}</string>
    <key>StandardErrorPath</key>
    <string>{log}</string>
</dict>
</plist>
"#,
        label = LABEL,
        exe = xml_escape(&exe.to_string_lossy()),
        log = xml_escape(&logfile.to_string_lossy()),
    );
    s
}

/// Escape the five XML metacharacters. Paths here contain none, but a plist is
/// XML and unescaped interpolation gives a file that fails to parse.
fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plist_names_the_program_and_the_label() {
        let body = plist_body(
            Path::new("/Users/someone/.cargo/bin/devbox-bridge"),
            Path::new("/Users/someone/Library/Logs/devbox-bridge.log"),
        );
        assert!(body.contains("<string>/Users/someone/.cargo/bin/devbox-bridge</string>"));
        assert!(body.contains(LABEL));
        assert!(body.starts_with("<?xml"));
    }

    #[test]
    fn plist_escapes_xml_metacharacters_in_paths() {
        let body = plist_body(
            Path::new("/tmp/a&b/devbox-bridge"),
            Path::new("/tmp/<log>.log"),
        );
        assert!(body.contains("/tmp/a&amp;b/devbox-bridge"));
        assert!(body.contains("/tmp/&lt;log&gt;.log"));
        assert!(!body.contains("a&b"));
    }

    #[test]
    fn paths_are_under_the_given_home() {
        let home = PathBuf::from("/Users/someone");
        assert_eq!(
            plist_path(&home),
            PathBuf::from("/Users/someone/Library/LaunchAgents/com.ariel.devbox-bridge.plist")
        );
        assert_eq!(
            log_path(&home),
            PathBuf::from("/Users/someone/Library/Logs/devbox-bridge.log")
        );
    }

    /// A bare name would not resolve under launchd's PATH.
    #[test]
    fn pngpaste_candidates_are_absolute() {
        assert!(PNGPASTE_CANDIDATES.iter().all(|p| p.starts_with('/')));
    }
}
