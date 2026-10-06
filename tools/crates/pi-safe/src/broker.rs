//! The credential broker, from pi-safe's side.
//!
//! The broker is cred-broker (tools/crates/cred-broker): one proxy on the
//! VM's localhost, shared by every sandbox, that puts the real tokens into
//! their requests. pi-safe starts it on demand (`cred-broker start`) and asks
//! it where it is (`cred-broker status --json`: port, CA, health URL).
//!
//! What pi-safe adds is the sandbox's side:
//!   - `HTTPS_PROXY` & co pointing at it, with the project's org as the proxy
//!     username (which picks the org's GitHub token)
//!   - a CA bundle (system CAs + the broker's) over the system bundle path
//!   - placeholders instead of tokens: `placeholder_env` and an auth.json
//!     whose OAuth entries hold no real token and never expire, so pi inside
//!     never tries to refresh

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde_json::{Map, Value, json};

use crate::config;

/// What the sandbox holds instead of a token. Any value works: the broker
/// replaces the header whatever it holds.
pub const PLACEHOLDER: &str = "pi-safe-broker";
/// Where the CA bundle goes inside the sandbox: over the system bundle, so
/// tools that read it (curl, git, gh, openssl) trust the broker unconfigured.
pub const CA_DEST: &str = "/etc/ssl/certs/ca-certificates.crt";
const SYSTEM_CA: &str = "/etc/ssl/certs/ca-certificates.crt";
/// `expires` of placeholder logins: 2100-01-01.
const NEVER_MS: u64 = 4_102_444_800_000;

pub struct Broker<'a> {
    pub cfg: &'a config::Broker,
    /// pi's real auth.json: the logins the placeholder copy is made from.
    pub auth: PathBuf,
}

/// The part of `cred-broker status --json` pi-safe uses.
#[derive(Debug, Deserialize)]
pub struct Info {
    pub pid: Option<u32>,
    pub port: u16,
    /// `http://cred-broker/health`, through the proxy (`--check`).
    pub health: String,
    /// The CA certificate; exists once the broker has started.
    pub ca: PathBuf,
}

impl<'a> Broker<'a> {
    pub fn new(cfg: &'a config::Broker, agent_dir: &Path) -> Self {
        Self {
            cfg,
            auth: agent_dir.join("auth.json"),
        }
    }

    /// `cred-broker <args>`: its stdout, or its error.
    fn cred_broker(&self, args: &[&str]) -> Result<String> {
        let Some((prog, base)) = self.cfg.command.split_first() else {
            bail!("broker.command is empty");
        };
        let out = Command::new(prog)
            .args(base)
            .args(args)
            .stdin(Stdio::null())
            .stderr(Stdio::inherit()) // its errors go straight to the user
            .output()
            .with_context(|| {
                format!(
                    "cannot run {prog} - install it: cargo install --path tools/crates/cred-broker"
                )
            })?;
        if !out.status.success() {
            bail!("`{prog} {}` failed", args.join(" "));
        }
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    }

    /// Where the broker is, and whether it runs.
    pub fn status(&self) -> Result<Info> {
        let json = self.cred_broker(&["status", "--json"])?;
        serde_json::from_str(&json).context("unexpected `cred-broker status --json`")
    }

    /// Starts the broker unless it runs (it outlives the sandbox).
    pub fn start(&self) -> Result<Info> {
        self.cred_broker(&["start"])?;
        self.status()
    }

    /// System CAs plus the broker's, at `out`; rewritten only when changed.
    pub fn ca_bundle(&self, info: &Info, out: &Path) -> Result<()> {
        let mut bundle =
            fs::read_to_string(SYSTEM_CA).with_context(|| format!("cannot read {SYSTEM_CA}"))?;
        let own = fs::read_to_string(&info.ca).with_context(|| {
            format!("cannot read {} (start the broker once)", info.ca.display())
        })?;
        if !bundle.ends_with('\n') {
            bundle.push('\n');
        }
        bundle.push_str("# cred-broker\n");
        bundle.push_str(&own);
        if fs::read_to_string(out).ok().as_deref() != Some(bundle.as_str()) {
            fs::write(out, bundle)?;
        }
        Ok(())
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

    /// The sandbox environment for the broker at `port`. `hint`: the
    /// project's org, sent as the proxy username; it picks the GitHub token.
    pub fn env(&self, hint: &str, port: u16) -> Vec<(String, String)> {
        let proxy = format!("http://{}:pi-safe@127.0.0.1:{port}", url_user(hint));
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

    /// The contract with cred-broker: what `status --json` prints.
    #[test]
    fn reads_cred_broker_status() {
        let json = r#"{
            "running": true, "pid": 42, "port": 18080,
            "health": "http://cred-broker/health",
            "ca": "/s/ca.pem", "requests": "/s/requests.jsonl", "log": "/s/broker.log"
        }"#;
        let info: Info = serde_json::from_str(json).unwrap();
        assert_eq!((info.pid, info.port), (Some(42), 18080));
        assert_eq!(info.health, "http://cred-broker/health");
        assert_eq!(info.ca, Path::new("/s/ca.pem"));
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
