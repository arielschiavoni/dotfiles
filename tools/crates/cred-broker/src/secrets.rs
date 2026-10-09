//! Where the real credentials come from: commands (gopass, pi), the broker's
//! environment, and pi's real auth.json. They stay in this process.

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use serde_json::Value;

use crate::config::{HeaderRule, Provider};

/// A login token from auth.json is used while it has this much time left;
/// then pi is asked for a fresh one (pi refreshes at the same point).
const MIN_VALIDITY: Duration = Duration::from_secs(5 * 60);
const COMMAND_TIMEOUT: Duration = Duration::from_secs(60);

pub struct Secrets {
    /// pi's real auth.json: the store of its logins, shared with plain pi.
    auth: PathBuf,
    /// GitHub and header secrets: read once, kept until a 401. Keyed by
    /// [`Secrets::github_key`] / [`Secrets::header_key`].
    cache: Mutex<HashMap<String, String>>,
    /// Concurrent model requests with an expiring token: one pi refresh.
    refresh: tokio::sync::Mutex<()>,
}

impl Secrets {
    pub fn new(auth: PathBuf) -> Self {
        Self {
            auth,
            cache: Mutex::default(),
            refresh: tokio::sync::Mutex::new(()),
        }
    }

    pub fn github_key(org: &str) -> String {
        format!("github:{org}")
    }

    pub fn header_key(h: &HeaderRule) -> String {
        format!("header:{}", h.name)
    }

    /// Drops a cached secret (it was rejected; it may have been rotated).
    pub fn forget(&self, key: &str) {
        self.cache.lock().unwrap().remove(key);
    }

    /// Token of org `org`: `command` with `{org}` replaced. An org without a
    /// token of its own gets `default` from the command (gopass fallback).
    pub async fn github_token(&self, org: &str, command: &[String]) -> Result<String> {
        let key = Self::github_key(org);
        if let Some(t) = self.cached(&key) {
            return Ok(t);
        }
        let token = run(&with(command, "{org}", org)).await?;
        if token.is_empty() {
            bail!("empty token from {} for '{org}'", command[0]);
        }
        Ok(self.store(key, token))
    }

    /// The secret of a header rule, from its command or the environment.
    pub async fn header_secret(&self, h: &HeaderRule) -> Result<String> {
        let key = Self::header_key(h);
        if let Some(s) = self.cached(&key) {
            return Ok(s);
        }
        let secret = match (&h.secret_command, &h.secret_env) {
            (Some(cmd), _) => run(cmd).await?,
            (None, Some(var)) => std::env::var(var).unwrap_or_default(),
            (None, None) => bail!("rule '{}' has no secret_command or secret_env", h.name),
        };
        if secret.is_empty() {
            bail!(
                "no secret for rule '{}' - check its source in config.toml",
                h.name
            );
        }
        Ok(self.store(key, secret))
    }

    /// Access token of pi's login `p`, and whether pi had to refresh it.
    /// auth.json is read on every request (it is tiny), so a refresh done
    /// by plain pi is seen at once.
    pub async fn login_token(&self, p: Provider, command: &[String]) -> Result<(String, bool)> {
        let _one_at_a_time = self.refresh.lock().await;
        // fast path: the stored token still has time left
        let entry = self.login(p)?;
        let left = entry.get("expires").and_then(Value::as_u64).unwrap_or(0);
        if let Some(access) = entry.get("access").and_then(Value::as_str)
            && left > now_ms() + MIN_VALIDITY.as_millis() as u64
        {
            return Ok((access.to_string(), false));
        }
        // about to expire (every few hours): pi refreshes it under its own
        // lock, saves it to auth.json and prints it
        let token = run(&with(command, "{provider}", p.name())).await?;
        Ok((token, true))
    }

    /// The GitHub OAuth token of pi's Copilot login (`refresh`; it does not
    /// expire): the account whose Copilot subscription the models use.
    pub fn copilot_github_token(&self) -> Result<String> {
        self.login(Provider::Copilot)?
            .get("refresh")
            .and_then(Value::as_str)
            .map(str::to_string)
            .ok_or_else(|| anyhow!("no github-copilot login in auth.json - /login in pi"))
    }

    /// The auth.json entry of login `p`; empty if there is none (then pi's
    /// command reports it: "not logged in").
    fn login(&self, p: Provider) -> Result<Value> {
        let text = match std::fs::read_to_string(&self.auth) {
            Ok(t) => t,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Value::Null),
            Err(e) => {
                return Err(e).with_context(|| format!("cannot read {}", self.auth.display()));
            }
        };
        let doc: Value = serde_json::from_str(&text)
            .with_context(|| format!("invalid {}", self.auth.display()))?;
        let entry = &doc[p.name()];
        Ok(if entry["type"] == "oauth" {
            entry.clone()
        } else {
            Value::Null
        })
    }

    fn cached(&self, key: &str) -> Option<String> {
        self.cache.lock().unwrap().get(key).cloned()
    }

    fn store(&self, key: String, value: String) -> String {
        self.cache.lock().unwrap().insert(key, value.clone());
        value
    }
}

/// stdout of a secret command. Runs in $HOME so that it never picks up the
/// config of the project the broker was started from.
pub async fn run(cmd: &[String]) -> Result<String> {
    let out = output(cmd, COMMAND_TIMEOUT).await?;
    if !out.status.success() {
        bail!("{}", failure(cmd, &out));
    }
    stdout(cmd, out)
}

/// A command's output, whatever its exit status; killed after `timeout`.
pub async fn output(cmd: &[String], timeout: Duration) -> Result<std::process::Output> {
    let Some((prog, args)) = cmd.split_first() else {
        bail!("no command configured in config.toml");
    };
    let mut command = tokio::process::Command::new(prog);
    command.args(args).stdin(Stdio::null()).kill_on_drop(true);
    if let Some(home) = std::env::var_os("HOME") {
        command.current_dir(home);
    }
    tokio::time::timeout(timeout, command.output())
        .await
        .map_err(|_| anyhow!("{prog} timed out"))?
        .with_context(|| format!("cannot run {prog}"))
}

/// `prog exited N: <last stderr line>`. That line goes into the 502 the
/// sandbox sees: tools print errors there, never the secret.
pub fn failure(cmd: &[String], out: &std::process::Output) -> String {
    let stderr = String::from_utf8_lossy(&out.stderr);
    let why: String = stderr
        .trim()
        .lines()
        .last()
        .unwrap_or("")
        .chars()
        .take(200)
        .collect();
    let prog = cmd.first().map_or("", String::as_str);
    format!("{prog} exited {}: {why}", out.status.code().unwrap_or(-1))
}

/// The trimmed stdout of a command that succeeded.
pub fn stdout(cmd: &[String], out: std::process::Output) -> Result<String> {
    let prog = cmd.first().map_or("", String::as_str);
    Ok(String::from_utf8(out.stdout)
        .with_context(|| format!("{prog} printed no text"))?
        .trim()
        .to_string())
}

/// `cmd` with `placeholder` replaced in every argument.
fn with(cmd: &[String], placeholder: &str, value: &str) -> Vec<String> {
    cmd.iter().map(|a| a.replace(placeholder, value)).collect()
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// pi and gopass are replaced by `echo`/`sh`, which print the "secret".
    fn cmd(args: &[&str]) -> Vec<String> {
        args.iter().map(|s| s.to_string()).collect()
    }

    fn secrets(auth_json: &str) -> (Secrets, PathBuf) {
        let dir = crate::test_dir("secrets");
        let auth = dir.join("auth.json");
        std::fs::write(&auth, auth_json).unwrap();
        (Secrets::new(auth), dir)
    }

    fn copilot_login(minutes_left: i64) -> String {
        let expires = now_ms() as i64 + minutes_left * 60_000;
        format!(
            r#"{{"github-copilot": {{"type": "oauth", "refresh": "gho-login", "access": "stored", "expires": {expires}}}}}"#
        )
    }

    #[tokio::test]
    async fn valid_login_token_comes_from_auth_json_without_pi() {
        let (s, dir) = secrets(&copilot_login(60));
        let got = s
            .login_token(Provider::Copilot, &cmd(&["false"]))
            .await
            .unwrap();
        assert_eq!(got, ("stored".into(), false));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn expiring_login_token_is_refreshed_by_pi() {
        let (s, dir) = secrets(&copilot_login(2));
        let pi = cmd(&["echo", "fresh-{provider}"]);
        let got = s.login_token(Provider::Copilot, &pi).await.unwrap();
        assert_eq!(got, ("fresh-github-copilot".into(), true));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn pi_errors_reach_the_client() {
        let (s, dir) = secrets("{}");
        let pi = cmd(&["sh", "-c", "echo not logged in >&2; exit 1"]);
        let err = s.login_token(Provider::Anthropic, &pi).await.unwrap_err();
        assert_eq!(err.to_string(), "sh exited 1: not logged in");
        let err = s.login_token(Provider::Anthropic, &[]).await.unwrap_err();
        assert!(err.to_string().contains("no command configured"));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn copilot_github_token_is_the_login_refresh_token() {
        let (s, dir) = secrets(&copilot_login(-10)); // expiry does not matter
        assert_eq!(s.copilot_github_token().unwrap(), "gho-login");
        std::fs::write(dir.join("auth.json"), "{}").unwrap();
        assert!(s.copilot_github_token().is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn github_tokens_are_cached_until_forgotten() {
        let (s, dir) = secrets("{}");
        let counter = dir.join("runs");
        // prints the org and counts its runs
        let gopass = cmd(&[
            "sh",
            "-c",
            &format!("echo x >> {}; echo tok-{{org}}", counter.display()),
        ]);
        assert_eq!(s.github_token("ASG", &gopass).await.unwrap(), "tok-ASG");
        assert_eq!(s.github_token("ASG", &gopass).await.unwrap(), "tok-ASG");
        s.forget(&Secrets::github_key("ASG"));
        s.github_token("ASG", &gopass).await.unwrap();
        assert_eq!(
            std::fs::read_to_string(&counter).unwrap().lines().count(),
            2
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn header_secret_must_not_be_empty() {
        let (s, dir) = secrets("{}");
        let rule = |secret_command| HeaderRule {
            name: "jira".into(),
            host: "h".into(),
            path: "/".into(),
            header: "Authorization".into(),
            value: "Bearer {secret}".into(),
            secret_env: None,
            secret_command: Some(secret_command),
        };
        assert_eq!(
            s.header_secret(&rule(cmd(&["echo", "pat"]))).await.unwrap(),
            "pat"
        );
        let empty = HeaderRule {
            name: "x".into(),
            ..rule(cmd(&["true"]))
        };
        let err = s.header_secret(&empty).await.unwrap_err();
        assert!(err.to_string().contains("no secret for rule 'x'"), "{err}");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
