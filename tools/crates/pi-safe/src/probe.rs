//! `pi-safe --check`: the binary mounts itself into the sandbox and runs
//! `pi-safe __probe <expectations>` there, so it sees exactly what the agent
//! sees. Unit tests cover the mount *plan*; this covers what bwrap, pasta and
//! the kernel actually make of it (worth re-running after upgrades).

use std::fs::{self, OpenOptions};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Duration;

use serde::{Deserialize, Serialize};

/// Where the binary is mounted inside the sandbox (under the empty /run).
pub const SANDBOX_PATH: &str = "/run/pi-safe";
/// Hidden first argument that switches the binary into probe mode.
pub const ARG: &str = "__probe";

const HIDDEN_HOME: &[&str] = &[
    ".ssh",
    ".aws",
    ".gnupg",
    ".docker",
    ".config/gh",
    ".config/gopass",
    ".local/share/gopass",
    ".claude",
    ".claude.json",
];
const HIDDEN_SYSTEM: &[&str] = &[
    "/run/docker.sock",
    "/var/run/docker.sock",
    "/run/containerd",
    "/run/user",
];

/// What the sandbox should look like, computed outside and passed in.
#[derive(Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Expect {
    pub project: PathBuf,
    pub project_read_only: Vec<PathBuf>,
    pub read_only: Vec<PathBuf>,
    pub hidden: Vec<PathBuf>,
    pub pi_writable: Vec<PathBuf>,
    pub pi_read_only: Vec<PathBuf>,
    pub command: String,
    pub listening: Vec<SocketAddr>,
    pub allowed_ports: Vec<u16>,
    pub internet: bool,
}

pub fn run(expect: &str) -> ExitCode {
    let e: Expect = match toml::from_str(expect) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("pi-safe: bad probe input: {err}");
            return ExitCode::from(2);
        }
    };
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let mut r = Report::default();

    r.section("files");
    for p in HIDDEN_HOME {
        r.expect(!home.join(p).exists(), format!("~/{p} hidden"));
    }
    for p in &e.read_only {
        r.expect(!writable(p), format!("{} read-only", p.display()));
    }
    r.expect(writable(&e.project), "project writable".into());
    for p in &e.project_read_only {
        r.expect(!writable(p), format!("{} read-only", p.display()));
    }
    for h in &e.hidden {
        let empty = match fs::metadata(h) {
            Ok(m) if m.is_dir() => fs::read_dir(h).is_ok_and(|mut d| d.next().is_none()),
            Ok(m) => m.len() == 0,
            Err(_) => false,
        };
        r.expect(empty, format!("hidden (empty): {}", h.display()));
    }

    r.section("pi");
    for p in &e.pi_writable {
        r.expect(writable(p), format!("{} writable (shared)", name(p)));
    }
    for p in &e.pi_read_only {
        r.expect(!writable(p), format!("{} read-only", name(p)));
    }
    r.expect(on_path(&e.command), format!("{} on PATH", e.command));

    r.section("processes and sockets");
    for p in HIDDEN_SYSTEM {
        r.expect(!Path::new(p).exists(), format!("{p} hidden"));
    }
    let tmux = std::env::var_os("TMUX").is_some()
        || dir_has(Path::new("/tmp"), |n| n.starts_with("tmux-"));
    r.expect(!tmux, "tmux socket hidden".into());
    let pids = fs::read_dir("/proc").map_or(0, |d| {
        d.flatten()
            .filter(|e| {
                e.file_name()
                    .to_string_lossy()
                    .bytes()
                    .all(|b| b.is_ascii_digit())
            })
            .count()
    });
    r.expect(pids < 20, "own pid namespace".into());
    let leaks = secret_env_names(std::env::vars().map(|(k, _)| k));
    let what = if leaks.is_empty() {
        "no secret env vars".to_string()
    } else {
        format!("no secret env vars: {}", leaks.join(" "))
    };
    r.expect(leaks.is_empty(), what);

    r.section("network");
    for addr in &e.listening {
        let allowed = e.allowed_ports.contains(&addr.port());
        let open = TcpStream::connect_timeout(addr, Duration::from_secs(2)).is_ok();
        let what = if allowed { "allowed" } else { "blocked" };
        r.expect(open == allowed, format!("VM {addr} {what}"));
    }
    let what = if e.internet {
        "internet works"
    } else {
        "no internet"
    };
    r.expect(internet() == e.internet, what.into());

    r.finish()
}

#[derive(Default)]
struct Report {
    fails: usize,
}

impl Report {
    fn section(&self, name: &str) {
        println!("[{name}]");
    }

    fn expect(&mut self, ok: bool, what: String) {
        if ok {
            println!("  ok    {what}");
        } else {
            println!("  FAIL  {what}");
            self.fails += 1;
        }
    }

    fn finish(self) -> ExitCode {
        println!();
        if self.fails == 0 {
            println!("pi-safe: all checks passed");
            ExitCode::SUCCESS
        } else {
            println!("pi-safe: {} check(s) failed", self.fails);
            ExitCode::from(1)
        }
    }
}

/// Dirs: a probe file can be created. Files: they open for writing - without
/// truncating or writing, so a real file is never modified. Missing: false.
fn writable(p: &Path) -> bool {
    if p.is_dir() {
        let probe = p.join(format!(".pi-safe-probe.{}", std::process::id()));
        let ok = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&probe)
            .is_ok();
        if ok {
            let _ = fs::remove_file(&probe);
        }
        ok
    } else {
        p.exists() && OpenOptions::new().write(true).open(p).is_ok()
    }
}

fn name(p: &Path) -> String {
    p.file_name()
        .map_or_else(|| p.display().to_string(), |n| n.to_string_lossy().into())
}

fn dir_has(dir: &Path, pred: impl Fn(&str) -> bool) -> bool {
    fs::read_dir(dir).is_ok_and(|d| d.flatten().any(|e| pred(&e.file_name().to_string_lossy())))
}

fn on_path(cmd: &str) -> bool {
    let path = std::env::var("PATH").unwrap_or_default();
    path.split(':').any(|d| {
        fs::metadata(Path::new(d).join(cmd))
            .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
    })
}

/// DNS + an outbound TCP connection; no HTTP needed to prove egress.
fn internet() -> bool {
    ("api.github.com", 443)
        .to_socket_addrs()
        .is_ok_and(|mut addrs| {
            addrs.any(|a| TcpStream::connect_timeout(&a, Duration::from_secs(5)).is_ok())
        })
}

/// Variable *names* that look like credentials (values are never printed).
fn secret_env_names(names: impl Iterator<Item = String>) -> Vec<String> {
    const MARKERS: &[&str] = &[
        "token",
        "secret",
        "passw",
        "apikey",
        "api_key",
        "credential",
        "ssh_auth",
    ];
    let mut leaks: Vec<String> = names
        .filter(|n| {
            let l = n.to_lowercase();
            l.starts_with("aws_") || MARKERS.iter().any(|m| l.contains(m))
        })
        .collect();
    leaks.sort();
    leaks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags_secret_env_names() {
        let names = [
            "GITHUB_TOKEN",
            "OPENAI_API_KEY",
            "AWS_PROFILE",
            "TERM",
            "PATH",
            "SSH_AUTH_SOCK",
        ];
        let leaks = secret_env_names(names.iter().map(|s| s.to_string()));
        assert_eq!(
            leaks,
            [
                "AWS_PROFILE",
                "GITHUB_TOKEN",
                "OPENAI_API_KEY",
                "SSH_AUTH_SOCK"
            ]
        );
    }

    #[test]
    fn writable_never_modifies_files() {
        let dir = std::env::temp_dir().join(format!("pi-safe-probe-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("settings.json");
        fs::write(&file, "keep").unwrap();
        assert!(writable(&dir));
        assert!(writable(&file));
        assert!(!writable(&dir.join("missing")));
        assert_eq!(fs::read_to_string(&file).unwrap(), "keep");
        assert_eq!(
            fs::read_dir(&dir).unwrap().count(),
            1,
            "probe file left behind"
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn expectations_round_trip_through_toml() {
        let e = Expect {
            project: "/p".into(),
            listening: vec![
                "127.0.0.1:3000".parse().unwrap(),
                "[::1]:22".parse().unwrap(),
            ],
            allowed_ports: vec![3000],
            internet: true,
            command: "pi".into(),
            ..Default::default()
        };
        let text = toml::to_string(&e).unwrap();
        assert_eq!(toml::from_str::<Expect>(&text).unwrap(), e);
    }
}
