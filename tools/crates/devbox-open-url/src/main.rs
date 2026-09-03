//! devbox-open-url — the macOS half of the devbox URL opener.
//!
//! Runs as a launchd user agent, listens on `127.0.0.1:17325`, and hands every
//! URL it receives to `/usr/bin/open`. The guest VM reaches it through the SSH
//! reverse tunnel configured by `devbox/scripts/ssh-config.sh`.
//!
//! ```text
//! devbox-open-url             run the daemon (this is what launchd invokes)
//! devbox-open-url --install   write the launchd plist and load it
//! devbox-open-url --status    is it installed, loaded, and listening?
//! ```
//!
//! `--install` lives here rather than in a shell script because the plist must
//! name an absolute path to the program, and [`std::env::current_exe`] knows it
//! — no `$HOME` expansion into XML, and no stale-path bugs.
//!
//! It cannot run from Lima provisioning: those scripts execute inside the guest
//! (`devbox/lima.yaml`), which has no access to `launchctl` here. Host-side
//! setup is driven by `devbox/scripts/create.sh`.
//!
//! Exit codes follow `tools/README.md`: 0 success, 1 expected negative, 2 tool
//! failure.

use std::fmt::Write as _;
use std::fs;
use std::io::Write as _;
use std::net::{TcpListener, TcpStream};
use std::os::unix::fs::MetadataExt as _;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use devbox_open_url::{HOST, PORT, Response, normalize, read_framed_line};

/// `com.ariel.` matches the other hand-written agents in `~/Library/LaunchAgents`.
const LABEL: &str = "com.ariel.devbox-open-url";

/// Absolute, not a `PATH` lookup: launchd hands us an environment we do not
/// control.
const OPEN_BIN: &str = "/usr/bin/open";

/// The accept loop is serial, so a stalled guest must not be able to wedge it.
const IO_TIMEOUT: Duration = Duration::from_secs(5);

const USAGE: &str = "\
devbox-open-url — open URLs sent from the devbox VM in the macOS browser

USAGE:
    devbox-open-url              run the daemon in the foreground
    devbox-open-url --install    write the launchd plist and (re)load it
    devbox-open-url --status     report installed / loaded / listening
    devbox-open-url --help

The daemon listens on 127.0.0.1:17325 and passes http(s) URLs to `open`.
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
            eprintln!("devbox-open-url: unknown argument {other:?}\n");
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
            eprintln!("devbox-open-url: {msg}");
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

    // Serial on purpose: `open` returns in milliseconds for one user, so a
    // thread per connection would add an unbounded-growth failure mode for
    // no throughput.
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
        // Liveness probe from `--status`. Logging it would make every status
        // check look like a failure.
        Ok(None) => return,
        Err(e) => {
            log(&format!("read failed: {e}"));
            // Best effort — the peer may already be gone.
            let _ = respond(&stream, &Response::Err(format!("read failed: {e}")));
            return;
        }
    };

    // Re-validate: the client checks too, but the tunnel is a trust boundary
    // and this is the side that launches something.
    let response = match normalize(&line) {
        Err(rejection) => {
            log(&format!("rejected {line:?}: {rejection}"));
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
    };

    if let Err(e) = respond(&stream, &response) {
        log(&format!("could not write response: {e}"));
    }
}

fn respond(mut stream: &TcpStream, response: &Response) -> std::io::Result<()> {
    stream.write_all(response.encode().as_bytes())?;
    stream.flush()
}

/// Hand the URL to `open` as one `argv` element — no shell, nothing to escape.
/// With `normalize` guaranteeing an `http(s)://` prefix, `open` cannot be
/// steered into treating it as a flag, a file, or an application.
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

/// Timestamped line to stderr; launchd captures it into the plist's log file.
/// Epoch seconds because formatting a date needs a calendar implementation and
/// this crate has no dependencies — read them with `date -r <secs>`.
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
    home.join("Library/Logs/devbox-open-url.log")
}

/// The launchd domain, e.g. `gui/501`. The uid comes from the owner of `$HOME`
/// because std does not expose `getuid()` and shelling out to `id -u` for one
/// integer is worse.
fn gui_domain(home: &Path) -> Result<String, String> {
    let uid = fs::metadata(home)
        .map_err(|e| format!("cannot stat {}: {e}", home.display()))?
        .uid();
    Ok(format!("gui/{uid}"))
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

    // Unload first, so --install doubles as "reload after rebuilding". On a
    // first install there is nothing to unload and launchctl says "Boot-out
    // failed: 3: No such process" — expected, hence silenced.
    let _ = Command::new("/bin/launchctl")
        .args(["bootout", &format!("{domain}/{LABEL}")])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();

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

    Ok(format!(
        "installed and loaded {LABEL}\n  program: {}\n  plist:   {}\n  log:     {}",
        exe.display(),
        plist.display(),
        logfile.display()
    ))
}

fn status() -> ExitCode {
    let home = match home() {
        Ok(h) => h,
        Err(e) => {
            eprintln!("devbox-open-url: {e}");
            return ExitCode::from(2);
        }
    };

    let plist = plist_path(&home);
    let mut healthy = true;

    if plist.is_file() {
        println!("plist      OK        {}", plist.display());
    } else {
        println!(
            "plist      MISSING   {}  (run: devbox-open-url --install)",
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
            println!(
                "launchd    MISSING   {LABEL} is not loaded  (run: devbox-open-url --install)"
            );
            healthy = false;
        }
    }

    // The only check that proves it works. This is the host end of the
    // tunnel, not the guest end.
    let addr = format!("{HOST}:{PORT}");
    match TcpStream::connect(&addr) {
        Ok(_) => println!("listening  OK        {addr}"),
        Err(e) => {
            println!("listening  FAILED    {addr}: {e}");
            healthy = false;
        }
    }

    if healthy {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}

/// `KeepAlive` restarts the daemon if it dies; `ThrottleInterval` stops that
/// becoming a hot loop when the failure is permanent, such as the port already
/// being bound.
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
/// XML and unescaped interpolation is how you get a file that fails to parse.
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
            Path::new("/Users/someone/.cargo/bin/devbox-open-url"),
            Path::new("/Users/someone/Library/Logs/devbox-open-url.log"),
        );
        assert!(body.contains("<string>/Users/someone/.cargo/bin/devbox-open-url</string>"));
        assert!(body.contains(LABEL));
        assert!(body.starts_with("<?xml"));
    }

    #[test]
    fn plist_escapes_xml_metacharacters_in_paths() {
        let body = plist_body(
            Path::new("/tmp/a&b/devbox-open-url"),
            Path::new("/tmp/<log>.log"),
        );
        assert!(body.contains("/tmp/a&amp;b/devbox-open-url"));
        assert!(body.contains("/tmp/&lt;log&gt;.log"));
        assert!(!body.contains("a&b"));
    }

    #[test]
    fn paths_are_under_the_given_home() {
        let home = PathBuf::from("/Users/someone");
        assert_eq!(
            plist_path(&home),
            PathBuf::from("/Users/someone/Library/LaunchAgents/com.ariel.devbox-open-url.plist")
        );
        assert_eq!(
            log_path(&home),
            PathBuf::from("/Users/someone/Library/Logs/devbox-open-url.log")
        );
    }
}
