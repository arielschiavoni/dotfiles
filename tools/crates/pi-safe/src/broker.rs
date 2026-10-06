//! The credential broker: one mitmproxy (`mitmdump -s broker/broker.py`) on
//! the VM's localhost, shared by every sandbox and started on demand.
//!
//! The sandbox reaches it through a pasta host port and gets:
//!   - `HTTPS_PROXY` & co pointing at it, with the project's org as the proxy
//!     username (a hint for GitHub requests that name no org)
//!   - a CA bundle (system CAs + the broker's) over the system bundle path
//!   - placeholders instead of tokens: `placeholder_env` and an auth.json
//!     whose OAuth entries hold no real token and never expire, so pi inside
//!     never tries to refresh
//!
//! The broker reads the real tokens (gopass, env, pi's real auth.json) and
//! puts them into the requests; see the docstring of broker.py. It is a
//! detached process (`setsid`) and outlives the sandbox that started it.

use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use serde_json::{Map, Value, json};

use crate::config::{self, expand};

/// What the sandbox holds instead of a token (broker.py knows it too).
pub const PLACEHOLDER: &str = "pi-safe-broker";
/// Host of the broker's own endpoints (health), answered by the proxy itself.
pub const HOST: &str = "pi-safe-broker";
/// Where the CA bundle goes inside the sandbox: over the system bundle, so
/// tools that read it (curl, git, gh, openssl) trust the broker unconfigured.
pub const CA_DEST: &str = "/etc/ssl/certs/ca-certificates.crt";
const SYSTEM_CA: &str = "/etc/ssl/certs/ca-certificates.crt";
/// `expires` of placeholder logins: 2100-01-01.
const NEVER_MS: u64 = 4_102_444_800_000;
const START_TIMEOUT: Duration = Duration::from_secs(20);

pub struct Broker<'a> {
    pub cfg: &'a config::Broker,
    /// Broker state: mitmproxy's CA (confdir), logs, the CA bundle.
    pub dir: PathBuf,
    /// pi's real auth.json, read by the broker (pi refreshes it).
    pub auth: PathBuf,
    rules: PathBuf,
    addon: PathBuf,
}

#[derive(Debug)]
pub struct Health {
    pub pid: u32,
}

impl<'a> Broker<'a> {
    pub fn new(cfg: &'a config::Broker, state_dir: &Path, agent_dir: &Path, home: &Path) -> Self {
        Self {
            cfg,
            dir: state_dir.join("broker"),
            auth: agent_dir.join("auth.json"),
            rules: expand(&cfg.rules, home),
            addon: expand(&cfg.addon, home),
        }
    }

    pub fn log(&self) -> PathBuf {
        self.dir.join("requests.jsonl")
    }

    pub fn proxy_log(&self) -> PathBuf {
        self.dir.join("mitmdump.log")
    }

    fn addr(&self) -> SocketAddr {
        SocketAddr::from(([127, 0, 0, 1], self.cfg.port))
    }

    /// The running broker, if one answers on the port.
    pub fn health(&self) -> Option<Health> {
        let body = self.get("/health").ok()?;
        let v: Value = serde_json::from_str(&body).ok()?;
        Some(Health {
            pid: v.get("pid")?.as_u64()? as u32,
        })
    }

    /// A plain-HTTP request to the broker's own host, through the proxy.
    fn get(&self, path: &str) -> Result<String> {
        let mut s = TcpStream::connect_timeout(&self.addr(), Duration::from_millis(500))?;
        s.set_read_timeout(Some(Duration::from_secs(3)))?;
        write!(
            s,
            "GET http://{HOST}{path} HTTP/1.1\r\nHost: {HOST}\r\nConnection: close\r\n\r\n"
        )?;
        let mut resp = String::new();
        s.read_to_string(&mut resp)?;
        let (head, body) = resp.split_once("\r\n\r\n").context("bad response")?;
        if !head.starts_with("HTTP/1.1 200") {
            bail!("{}", head.lines().next().unwrap_or_default());
        }
        Ok(body.to_string())
    }

    /// Starts the broker unless one is running; waits until it answers.
    pub fn start(&self) -> Result<Health> {
        if let Some(h) = self.health() {
            return Ok(h);
        }
        for (what, p) in [("addon", &self.addon), ("rules", &self.rules)] {
            if !p.is_file() {
                bail!("broker {what} {} not found", p.display());
            }
        }
        if TcpStream::connect_timeout(&self.addr(), Duration::from_millis(300)).is_ok() {
            bail!(
                "port {} is in use by something that is not the broker",
                self.cfg.port
            );
        }
        fs::create_dir_all(&self.dir)?;
        let log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.proxy_log())?;
        let Some((prog, args)) = self.cfg.command.split_first() else {
            bail!("broker.command is empty")
        };
        let set = |k: &str, v: &Path| format!("{k}={}", v.display());
        let status = Command::new("setsid")
            .arg("-f")
            .arg(prog)
            .args(args)
            .args(["--listen-host", "127.0.0.1", "--listen-port"])
            .arg(self.cfg.port.to_string())
            .args(["--set", "termlog_verbosity=warn", "--set", "flow_detail=0"])
            // stream request bodies over 10 MB (uploads) instead of buffering them;
            // responses are always streamed (broker.py)
            .args(["--set", "stream_large_bodies=10m"])
            .arg("--set")
            .arg(set("confdir", &self.dir))
            .arg("-s")
            .arg(&self.addon)
            .arg("--set")
            .arg(set("pi_safe_rules", &self.rules))
            .arg("--set")
            .arg(set("pi_safe_auth", &self.auth))
            .arg("--set")
            .arg(set("pi_safe_state", &self.dir))
            .stdin(Stdio::null())
            .stdout(log.try_clone()?)
            .stderr(log)
            .status()
            .context("cannot run setsid")?;
        if !status.success() {
            bail!("cannot start the broker ({prog})");
        }
        let deadline = Instant::now() + START_TIMEOUT;
        while Instant::now() < deadline {
            if let Some(h) = self.health() {
                return Ok(h);
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        bail!(
            "the broker did not come up within {}s - see {}",
            START_TIMEOUT.as_secs(),
            self.proxy_log().display()
        )
    }

    /// Stops the running broker; false if none was running.
    pub fn stop(&self) -> Result<bool> {
        let Some(h) = self.health() else {
            return Ok(false);
        };
        let ok = Command::new("kill")
            .arg(h.pid.to_string())
            .status()?
            .success();
        if !ok {
            bail!("cannot stop the broker (pid {})", h.pid);
        }
        // gone once the port is free, not when /health stops answering: the
        // exiting proxy still holds it for a moment, and `restart` needs it
        let deadline = Instant::now() + Duration::from_secs(10);
        while TcpStream::connect_timeout(&self.addr(), Duration::from_millis(200)).is_ok() {
            if Instant::now() > deadline {
                bail!("the broker (pid {}) did not stop", h.pid);
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        Ok(true)
    }

    /// System CAs plus the broker's, rewritten only when it changed.
    pub fn ca_bundle(&self) -> Result<PathBuf> {
        let ca = self.dir.join("mitmproxy-ca-cert.pem");
        let mut bundle =
            fs::read_to_string(SYSTEM_CA).with_context(|| format!("cannot read {SYSTEM_CA}"))?;
        let own = fs::read_to_string(&ca)
            .with_context(|| format!("cannot read {} (start the broker once)", ca.display()))?;
        if !bundle.ends_with('\n') {
            bundle.push('\n');
        }
        bundle.push_str("# pi-safe broker\n");
        bundle.push_str(&own);
        let out = self.dir.join("ca-bundle.pem");
        if fs::read_to_string(&out).ok().as_deref() != Some(bundle.as_str()) {
            fs::write(&out, bundle)?;
        }
        Ok(out)
    }

    /// Writes the sandbox's auth.json to `dest`; returns the entries dropped.
    pub fn write_stub_auth(&self, dest: &Path) -> Result<Vec<String>> {
        let real = match fs::read_to_string(&self.auth) {
            Ok(t) => serde_json::from_str(&t)
                .with_context(|| format!("invalid {}", self.auth.display()))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Value::Object(Map::new()),
            Err(e) => {
                return Err(e).with_context(|| format!("cannot read {}", self.auth.display()));
            }
        };
        let (stub, dropped) = stub_auth(&real, &self.cfg.providers);
        let mut f = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(dest)
            .with_context(|| format!("cannot write {}", dest.display()))?;
        f.write_all(serde_json::to_string_pretty(&stub)?.as_bytes())?;
        Ok(dropped)
    }

    /// The sandbox environment for the broker. `hint`: the project's org.
    pub fn env(&self, hint: &str) -> Vec<(String, String)> {
        let proxy = format!(
            "http://{}:pi-safe@127.0.0.1:{}",
            url_user(hint),
            self.cfg.port
        );
        let mut env: Vec<(String, String)> = Vec::new();
        for k in ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"] {
            env.push((k.into(), proxy.clone()));
        }
        for k in ["NO_PROXY", "no_proxy"] {
            env.push((k.into(), "localhost,127.0.0.1,::1".into()));
        }
        env.push(("NODE_USE_ENV_PROXY".into(), "1".into()));
        for k in [
            "NODE_EXTRA_CA_CERTS",
            "SSL_CERT_FILE",
            "REQUESTS_CA_BUNDLE",
            "CURL_CA_BUNDLE",
            "GIT_SSL_CAINFO",
        ] {
            env.push((k.into(), CA_DEST.into()));
        }
        for k in &self.cfg.placeholder_env {
            env.push((k.clone(), PLACEHOLDER.into()));
        }
        // git settings for the sandbox only, passed as env: git reads
        // GIT_CONFIG_COUNT pairs of GIT_CONFIG_KEY_<i> / _VALUE_<i> as if set
        // with `git -c`, over ~/.config/git. They concern git's network commands
        // (fetch, pull, clone, push; commit is local), whose GitHub token the
        // broker adds on the way out.
        for (k, v) in [
            ("GIT_CONFIG_COUNT", "2"),
            // No credential helper: ~/.config/git's (multiaccount) needs gopass,
            // which is not in the sandbox. git only runs it if GitHub rejects
            // the broker's token; without it that is a plain auth error.
            ("GIT_CONFIG_KEY_0", "credential.helper"),
            ("GIT_CONFIG_VALUE_0", ""),
            // Always send the proxy username (the project org, see HTTPS_PROXY),
            // which picks the org's token. By default git sends it only when
            // the proxy asks, which it never does: a private repo of a
            // non-default org (ASG-SONG) would get the `default` token.
            ("GIT_CONFIG_KEY_1", "http.proxyAuthMethod"),
            ("GIT_CONFIG_VALUE_1", "basic"),
        ] {
            env.push((k.into(), v.into()));
        }
        env
    }
}

/// The org a project belongs to, as fish's GITHUB_TOKEN hook sees it:
/// `~/repos/<org>/...`, else `default`.
pub fn project_org(project: &Path, home: &Path) -> String {
    project
        .strip_prefix(home.join("repos"))
        .ok()
        .and_then(|rel| rel.components().next())
        .map(|c| c.as_os_str().to_string_lossy().into_owned())
        .unwrap_or_else(|| "default".into())
}

/// Only characters that need no escaping in a URL's userinfo.
fn url_user(s: &str) -> String {
    let u: String = s
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || "-._~".contains(*c))
        .collect();
    if u.is_empty() { "default".into() } else { u }
}

/// Placeholder logins for `providers`; every other entry is dropped.
fn stub_auth(real: &Value, providers: &[String]) -> (Value, Vec<String>) {
    let mut out = Map::new();
    let mut dropped = Vec::new();
    let Some(entries) = real.as_object() else {
        return (Value::Object(out), dropped);
    };
    for (name, entry) in entries {
        let oauth = entry.get("type").and_then(Value::as_str) == Some("oauth");
        if !(oauth && providers.contains(name)) {
            dropped.push(name.clone());
            continue;
        }
        let mut stub = json!({
            "type": "oauth",
            "refresh": PLACEHOLDER,
            "access": PLACEHOLDER,
            "expires": NEVER_MS,
        });
        match name.as_str() {
            // pi reads the API host from the token (proxy-ep=...)
            "github-copilot" => {
                let real_access = entry.get("access").and_then(Value::as_str).unwrap_or("");
                let ep = real_access
                    .split(';')
                    .find_map(|kv| kv.strip_prefix("proxy-ep="))
                    .unwrap_or("proxy.individual.githubcopilot.com");
                stub["access"] =
                    format!("tid={PLACEHOLDER};exp={};proxy-ep={ep};", NEVER_MS / 1000).into();
                for k in ["availableModelIds", "enterpriseUrl"] {
                    if let Some(v) = entry.get(k) {
                        stub[k] = v.clone();
                    }
                }
            }
            // pi switches to OAuth (Bearer, Claude Code headers) on this prefix
            "anthropic" => stub["access"] = format!("sk-ant-oat01-{PLACEHOLDER}").into(),
            _ => {}
        }
        out.insert(name.clone(), stub);
    }
    (Value::Object(out), dropped)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn providers() -> Vec<String> {
        vec!["github-copilot".into(), "anthropic".into()]
    }

    #[test]
    fn stub_keeps_no_secret_and_never_expires() {
        let real = json!({
            "github-copilot": {
                "type": "oauth", "refresh": "gho_REAL", "expires": 1,
                "access": "tid=REAL;exp=1;sku=x;proxy-ep=proxy.business.githubcopilot.com;8kp=1:REAL",
                "availableModelIds": ["gpt-5.5"]
            },
            "anthropic": {"type": "oauth", "refresh": "sk-ant-ort01-REAL", "access": "sk-ant-oat01-REAL", "expires": 1},
            "openai": {"type": "api_key", "key": "sk-REAL"}
        });
        let (stub, dropped) = stub_auth(&real, &providers());
        let text = stub.to_string();
        assert!(!text.contains("REAL"), "{text}");
        assert_eq!(dropped, ["openai"]);
        let cp = &stub["github-copilot"];
        assert_eq!(
            cp["access"],
            "tid=pi-safe-broker;exp=4102444800;proxy-ep=proxy.business.githubcopilot.com;"
        );
        assert_eq!(cp["availableModelIds"], json!(["gpt-5.5"]));
        assert_eq!(cp["expires"], NEVER_MS);
        assert_eq!(stub["anthropic"]["access"], "sk-ant-oat01-pi-safe-broker");
    }

    #[test]
    fn stub_drops_unserved_providers() {
        let real =
            json!({"anthropic": {"type": "oauth", "access": "a", "refresh": "r", "expires": 1}});
        let (stub, dropped) = stub_auth(&real, &["github-copilot".into()]);
        assert_eq!(stub, json!({}));
        assert_eq!(dropped, ["anthropic"]);
    }

    #[test]
    fn project_org_like_fish() {
        let home = Path::new("/h");
        assert_eq!(
            project_org(Path::new("/h/repos/ASG-SONG/app"), home),
            "ASG-SONG"
        );
        assert_eq!(project_org(Path::new("/h/share/x"), home), "default");
        assert_eq!(url_user("a b/c"), "abc");
        assert_eq!(url_user("//"), "default");
    }
}
