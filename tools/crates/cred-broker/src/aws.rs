//! AWS credentials for the sandbox: `http://cred-broker/aws/<profile>`, what
//! its `credential_process` asks (pi-safe writes the sandbox's ~/.aws/config).
//!
//! These credentials are handed *to* the sandbox: the AWS client signs each
//! request itself (SigV4). The sandbox gets the short-lived credentials of a
//! profile in `[aws] profiles` (a read-only role, 1h when chained); the SSO
//! token they are made from stays in this process's environment - it makes
//! credentials for every profile, admin ones included.
//!
//! A request:
//!   1. a profile not in `[aws] profiles`: 403
//!   2. cached credentials with more than MIN_LEFT left: those
//!   3. `credentials_command` (aws-session credentials): renews the role
//!      credentials, and the SSO token with its refresh token, silently
//!   4. it exits 1 - the SSO session has ended: `login_command` (aws sso
//!      login with a device code, and a tmux message), which waits until the
//!      login is approved in the browser; then 3 again
//!
//! One fetch at a time: concurrent requests wait, then find the cache filled,
//! so one login serves them all. After a login that was not approved, the
//! next one waits LOGIN_COOLDOWN, which keeps a looping agent to one browser
//! prompt per cooldown.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use jiff::{SignedDuration, Timestamp, Zoned};
use serde_json::Value;

use crate::config;
use crate::secrets::{self, failure, output};

/// Cached credentials are handed out while they have this much time left.
const MIN_LEFT: Duration = Duration::from_secs(5 * 60);
const COMMAND_TIMEOUT: Duration = Duration::from_secs(60);
/// How long a login waits for the approval in the browser.
pub const LOGIN_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const LOGIN_COOLDOWN: Duration = Duration::from_secs(5 * 60);

#[derive(Default)]
pub struct Aws {
    /// Profile -> credentials.
    cache: Mutex<HashMap<String, Cached>>,
    /// Held while fetching; the last login that was not approved.
    fetch: tokio::sync::Mutex<Option<FailedLogin>>,
}

struct Cached {
    json: String,
    /// Unix seconds of `Expiration`; 0 makes every request fetch again.
    expires: i64,
}

struct FailedLogin {
    at: Instant,
    when: Zoned,
}

/// Where the credentials came from, for requests.jsonl.
#[derive(Debug, PartialEq, Eq)]
pub enum Via {
    Cache,
    Command,
    Login,
}

impl Via {
    pub fn name(&self) -> &'static str {
        match self {
            Via::Cache => "cache",
            Via::Command => "command",
            Via::Login => "login",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    /// Not in `[aws] profiles`.
    NotServed,
    Failed(String),
}

/// What `credentials_command` gave.
enum Fetch {
    Ok(String, i64),
    LoginNeeded,
}

impl Aws {
    /// Credentials of `profile`, as credential_process JSON.
    pub async fn credentials(
        &self,
        cfg: &config::Aws,
        profile: &str,
    ) -> Result<(String, Via), Error> {
        if !cfg.serves(profile) {
            return Err(Error::NotServed);
        }
        if let Some(json) = self.cached(profile) {
            return Ok((json, Via::Cache));
        }
        let mut failed_login = self.fetch.lock().await;
        // filled while this request waited for the lock
        if let Some(json) = self.cached(profile) {
            return Ok((json, Via::Cache));
        }

        let creds = with(&cfg.credentials_command, profile);
        if let Fetch::Ok(json, expires) = fetch(&creds).await? {
            // logged in outside meanwhile (aws_login): the cooldown ends
            *failed_login = None;
            return Ok((self.store(profile, json, expires), Via::Command));
        }

        if let Some(f) = failed_login.as_ref()
            && f.at.elapsed() < LOGIN_COOLDOWN
        {
            let retry = f
                .when
                .checked_add(SignedDuration::try_from(LOGIN_COOLDOWN).unwrap_or_default())
                .unwrap_or_else(|_| f.when.clone());
            return Err(Error::Failed(format!(
                "AWS SSO login needed; the one started at {} was not approved - run \
                 aws_login outside the sandbox, or retry after {}",
                f.when.strftime("%H:%M"),
                retry.strftime("%H:%M"),
            )));
        }

        let login = with(&cfg.login_command, profile);
        crate::proxy::note(&format!(
            "aws: SSO login for {profile}, waiting for its approval in the browser"
        ));
        let result = match output(&login, LOGIN_TIMEOUT).await {
            Ok(out) if out.status.success() => Ok(()),
            Ok(out) => Err(failure(&login, &out)),
            Err(e) => Err(format!(
                "{e:#} (not approved within {} min)",
                LOGIN_TIMEOUT.as_secs() / 60
            )),
        };
        if let Err(why) = result {
            *failed_login = Some(FailedLogin {
                at: Instant::now(),
                when: Zoned::now(),
            });
            crate::proxy::note(&format!("aws: SSO login for {profile} failed: {why}"));
            return Err(Error::Failed(format!("AWS SSO login failed: {why}")));
        }
        *failed_login = None;

        match fetch(&creds).await? {
            Fetch::Ok(json, expires) => Ok((self.store(profile, json, expires), Via::Login)),
            Fetch::LoginNeeded => Err(Error::Failed(format!(
                "still no AWS credentials for {profile} after the SSO login"
            ))),
        }
    }

    fn cached(&self, profile: &str) -> Option<String> {
        let cache = self.cache.lock().unwrap();
        let c = cache.get(profile)?;
        let left = c.expires - Timestamp::now().as_second();
        (left > MIN_LEFT.as_secs() as i64).then(|| c.json.clone())
    }

    fn store(&self, profile: &str, json: String, expires: i64) -> String {
        let entry = Cached {
            json: json.clone(),
            expires,
        };
        self.cache.lock().unwrap().insert(profile.into(), entry);
        json
    }
}

/// Runs `credentials_command`: exit 0 credentials, 1 login needed.
async fn fetch(cmd: &[String]) -> Result<Fetch, Error> {
    let out = output(cmd, COMMAND_TIMEOUT)
        .await
        .map_err(|e| Error::Failed(format!("{e:#}")))?;
    match out.status.code() {
        Some(0) => {}
        Some(1) => return Ok(Fetch::LoginNeeded),
        _ => return Err(Error::Failed(failure(cmd, &out))),
    }
    let json = secrets::stdout(cmd, out).map_err(|e| Error::Failed(format!("{e:#}")))?;
    let doc: Value = serde_json::from_str(&json).unwrap_or_default();
    if doc.get("AccessKeyId").and_then(Value::as_str).is_none() {
        let prog = cmd.first().map_or("", String::as_str);
        return Err(Error::Failed(format!(
            "{prog} printed no credential_process JSON"
        )));
    }
    let expires = doc
        .get("Expiration")
        .and_then(Value::as_str)
        .and_then(|e| e.parse::<Timestamp>().ok())
        .map_or(0, Timestamp::as_second);
    Ok(Fetch::Ok(json, expires))
}

fn with(cmd: &[String], profile: &str) -> Vec<String> {
    cmd.iter()
        .map(|a| a.replace("{profile}", profile))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// aws-session replaced by `sh`: credentials once `logged-in` exists, and
    /// a login that creates it - or fails, with `fail-login`. Each run of
    /// either is counted in `runs`.
    fn cfg(dir: &Path, expires: &str) -> config::Aws {
        let d = dir.display();
        let creds = format!(
            "echo creds >> {d}/runs; [ -f {d}/logged-in ] || exit 1; \
             echo '{{\"Version\":1,\"AccessKeyId\":\"{{profile}}\",\"Expiration\":\"{expires}\"}}'"
        );
        let login = format!(
            "echo login >> {d}/runs; [ -f {d}/fail-login ] && {{ echo not approved >&2; exit 2; }}; \
             touch {d}/logged-in"
        );
        config::Aws {
            profiles: vec!["*.agent".into()],
            credentials_command: vec!["sh".into(), "-c".into(), creds],
            login_command: vec!["sh".into(), "-c".into(), login],
        }
    }

    fn runs(dir: &Path) -> Vec<String> {
        std::fs::read_to_string(dir.join("runs"))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    fn in_hours(h: i64) -> String {
        (Timestamp::now() + SignedDuration::from_hours(h)).to_string()
    }

    #[tokio::test]
    async fn only_served_profiles() {
        let dir = crate::test_dir("aws-served");
        let err = Aws::default()
            .credentials(&cfg(&dir, &in_hours(1)), "x.admin")
            .await;
        assert_eq!(err, Err(Error::NotServed));
        assert!(runs(&dir).is_empty());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn logs_in_once_then_serves_from_the_cache() {
        let dir = crate::test_dir("aws-login");
        let (aws, cfg) = (Aws::default(), cfg(&dir, &in_hours(1)));
        let (json, via) = aws.credentials(&cfg, "app.agent").await.unwrap();
        assert_eq!(via, Via::Login);
        assert!(json.contains(r#""AccessKeyId":"app.agent""#), "{json}");
        let (_, via) = aws.credentials(&cfg, "app.agent").await.unwrap();
        assert_eq!(via, Via::Cache);
        // another profile: it reuses the SSO login
        let (_, via) = aws.credentials(&cfg, "other.agent").await.unwrap();
        assert_eq!(via, Via::Command);
        assert_eq!(runs(&dir), ["creds", "login", "creds", "creds"]);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn expiring_credentials_are_fetched_again() {
        let dir = crate::test_dir("aws-expiring");
        std::fs::write(dir.join("logged-in"), "").unwrap();
        let soon = (Timestamp::now() + SignedDuration::from_mins(2)).to_string();
        let (aws, cfg) = (Aws::default(), cfg(&dir, &soon));
        for _ in 0..2 {
            let (_, via) = aws.credentials(&cfg, "app.agent").await.unwrap();
            assert_eq!(via, Via::Command);
        }
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn a_failed_login_is_not_retried_during_the_cooldown() {
        let dir = crate::test_dir("aws-cooldown");
        std::fs::write(dir.join("fail-login"), "").unwrap();
        let (aws, cfg) = (Aws::default(), cfg(&dir, &in_hours(1)));
        let Err(Error::Failed(first)) = aws.credentials(&cfg, "app.agent").await else {
            panic!("expected a failed login");
        };
        assert!(first.contains("not approved"), "{first}");
        let Err(Error::Failed(second)) = aws.credentials(&cfg, "app.agent").await else {
            panic!("expected the cooldown");
        };
        assert!(
            second.contains("run aws_login outside the sandbox"),
            "{second}"
        );
        assert_eq!(runs(&dir), ["creds", "login", "creds"]);

        // a login done outside ends the cooldown
        std::fs::write(dir.join("logged-in"), "").unwrap();
        let (_, via) = aws.credentials(&cfg, "app.agent").await.unwrap();
        assert_eq!(via, Via::Command);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn other_failures_carry_the_reason() {
        let dir = crate::test_dir("aws-failure");
        let cfg = config::Aws {
            profiles: vec!["*".into()],
            credentials_command: vec![
                "sh".into(),
                "-c".into(),
                "echo AccessDenied for {profile} >&2; exit 2".into(),
            ],
            login_command: vec!["false".into()],
        };
        let err = Aws::default().credentials(&cfg, "app.agent").await;
        assert_eq!(
            err,
            Err(Error::Failed(
                "sh exited 2: AccessDenied for app.agent".into()
            ))
        );
        let cfg = config::Aws {
            credentials_command: vec!["echo".into(), "not json".into()],
            ..cfg
        };
        let Err(Error::Failed(why)) = Aws::default().credentials(&cfg, "app.agent").await else {
            panic!("expected a failure");
        };
        assert!(why.contains("no credential_process JSON"), "{why}");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
