//! config.toml: where the broker listens, which credential goes to which
//! host, and where it is read from. No secrets in it. [`Config::route`]
//! decides, per request, what the proxy does with it.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// Port on 127.0.0.1.
    pub port: u16,
    /// CA, logs. `~` is expanded.
    pub state_dir: String,
    pub github: GitHub,
    pub oauth: OAuth,
    pub header: Vec<HeaderRule>,
    pub block: Vec<BlockRule>,
}

/// GitHub: the token of the sandbox's project org.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct GitHub {
    /// Host -> how the token is sent.
    pub hosts: BTreeMap<String, AuthScheme>,
    /// Prints the token of org `{org}`.
    pub token_command: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AuthScheme {
    /// `Authorization: Bearer <token>` (the REST and GraphQL API)
    Bearer,
    /// `Authorization: Basic x-access-token:<token>` (git over HTTPS)
    Basic,
}

/// pi's OAuth logins.
#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct OAuth {
    /// pi's real auth.json, where the logins are read from. `~` is expanded.
    pub auth: String,
    /// Prints a valid token of login `{provider}`, refreshing it if needed.
    pub token_command: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            port: 18080,
            state_dir: "~/.local/state/cred-broker".into(),
            github: GitHub::default(),
            oauth: OAuth::default(),
            header: Vec::new(),
            block: Vec::new(),
        }
    }
}

impl Default for OAuth {
    fn default() -> Self {
        Self {
            auth: "~/.pi/agent/auth.json".into(),
            token_command: Vec::new(),
        }
    }
}

/// A static header for a host + path prefix (Jira PAT).
#[derive(Debug, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HeaderRule {
    pub name: String,
    pub host: String,
    #[serde(default = "root")]
    pub path: String,
    pub header: String,
    /// The header value, `{secret}` replaced with the secret.
    pub value: String,
    /// The secret from the broker's environment...
    pub secret_env: Option<String>,
    /// ...or from a command's stdout.
    pub secret_command: Option<Vec<String>>,
}

/// Requests the sandbox may never make (token exchanges).
#[derive(Debug, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BlockRule {
    pub host: String,
    #[serde(default = "root")]
    pub path: String,
}

fn root() -> String {
    "/".into()
}

/// pi's logins, as named in auth.json. Their hosts are fixed by the
/// providers, so they are not in config.toml.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Provider {
    Copilot,
    Anthropic,
}

impl Provider {
    pub fn name(self) -> &'static str {
        match self {
            Provider::Copilot => "github-copilot",
            Provider::Anthropic => "anthropic",
        }
    }

    /// The login whose token the model API at `host` takes.
    fn for_host(host: &str) -> Option<Self> {
        if host.ends_with(".githubcopilot.com") {
            Some(Provider::Copilot)
        } else if host == "api.anthropic.com" {
            Some(Provider::Anthropic)
        } else {
            None
        }
    }
}

/// What the proxy does with a request; see [`Rules::route`].
#[derive(Debug, PartialEq)]
pub enum Route<'a> {
    /// Answer 403, never forward.
    Block(&'a BlockRule),
    /// Bearer token of pi's login (model requests).
    Login(Provider),
    /// Bearer GitHub token of pi's Copilot login: Copilot's plan and quota
    /// info (pi-quotas), for the account the model requests are charged to.
    CopilotInfo,
    /// The project org's GitHub token.
    GitHub(AuthScheme),
    /// A static header.
    Header(&'a HeaderRule),
    /// Forward unchanged.
    Pass,
}

impl Route<'_> {
    /// Name in requests.jsonl.
    pub fn name(&self) -> &str {
        match self {
            Route::Block(_) => "block",
            Route::Login(p) => p.name(),
            Route::CopilotInfo => "github-copilot",
            Route::GitHub(_) => "github",
            Route::Header(h) => &h.name,
            Route::Pass => "pass",
        }
    }
}

impl Config {
    /// `~/.config/cred-broker/config.toml`
    pub fn default_path() -> PathBuf {
        expand("~/.config/cred-broker/config.toml")
    }

    pub fn load(path: &Path) -> Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("cannot read {}", path.display()))?;
        toml::from_str(&text).with_context(|| format!("invalid {}", path.display()))
    }

    pub fn state_dir(&self) -> PathBuf {
        expand(&self.state_dir)
    }

    pub fn auth(&self) -> PathBuf {
        expand(&self.oauth.auth)
    }

    /// Whether to open the TLS of a CONNECT to `host`. Only hosts with a rule
    /// are decrypted; all other traffic is tunnelled as it is.
    pub fn intercepts(&self, host: &str) -> bool {
        Provider::for_host(host).is_some()
            || self.github.hosts.contains_key(host)
            || self.header.iter().any(|h| h.host == host)
            || self.block.iter().any(|b| b.host == host)
    }

    /// The first rule that applies to a request; `path` without the query.
    pub fn route(&self, host: &str, path: &str) -> Route<'_> {
        // blocks first: nothing else may make a blocked request pass
        if let Some(b) = self
            .block
            .iter()
            .find(|b| b.host == host && path_matches(path, &b.path))
        {
            return Route::Block(b);
        }
        if let Some(p) = Provider::for_host(host) {
            return Route::Login(p);
        }
        if host == "api.github.com" && path_matches(path, "/copilot_internal/") {
            return Route::CopilotInfo;
        }
        if let Some(&scheme) = self.github.hosts.get(host) {
            return Route::GitHub(scheme);
        }
        match self
            .header
            .iter()
            .find(|h| h.host == host && path_matches(path, &h.path))
        {
            Some(h) => Route::Header(h),
            None => Route::Pass,
        }
    }
}

/// `~/x` -> `$HOME/x`.
pub fn expand(path: &str) -> PathBuf {
    match (path.strip_prefix("~/"), std::env::var_os("HOME")) {
        (Some(rest), Some(home)) => PathBuf::from(home).join(rest),
        _ => PathBuf::from(path),
    }
}

/// `/jira/x` and `/jira` match `/jira/`; `/jiralike` does not.
pub fn path_matches(path: &str, prefix: &str) -> bool {
    prefix == "/" || path == prefix.trim_end_matches('/') || path.starts_with(prefix)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rules() -> Config {
        toml::from_str(
            r#"
            [github]
            hosts = { "api.github.com" = "bearer", "github.com" = "basic" }
            token_command = ["echo", "{org}"]
            [[header]]
            name = "jira"
            host = "jira.example"
            path = "/jira/"
            header = "Authorization"
            value = "Bearer {secret}"
            secret_env = "JIRA"
            [[block]]
            host = "api.github.com"
            path = "/copilot_internal/v2/token"
            "#,
        )
        .unwrap()
    }

    #[test]
    fn routes_in_order() {
        let r = rules();
        let route = |host, path| r.route(host, path).name().to_string();
        assert_eq!(
            route("api.github.com", "/copilot_internal/v2/token"),
            "block"
        );
        assert_eq!(
            route("api.github.com", "/copilot_internal/v2/token/x"),
            "block"
        );
        assert_eq!(
            route("api.github.com", "/copilot_internal/user"),
            "github-copilot"
        );
        assert_eq!(route("api.github.com", "/user"), "github");
        assert_eq!(
            r.route("github.com", "/o/r.git/info/refs"),
            Route::GitHub(AuthScheme::Basic)
        );
        assert_eq!(
            route("api.business.githubcopilot.com", "/models"),
            "github-copilot"
        );
        assert_eq!(route("api.anthropic.com", "/v1/messages"), "anthropic");
        assert_eq!(route("jira.example", "/jira/rest/api/2/search"), "jira");
        assert_eq!(route("jira.example", "/other"), "pass");
    }

    #[test]
    fn intercepts_only_hosts_with_a_rule() {
        let r = rules();
        for host in [
            "api.github.com",
            "github.com",
            "jira.example",
            "api.anthropic.com",
            "x.githubcopilot.com",
        ] {
            assert!(r.intercepts(host), "{host}");
        }
        for host in ["example.com", "githubcopilot.com.evil", "anthropic.com"] {
            assert!(!r.intercepts(host), "{host}");
        }
    }

    #[test]
    fn path_prefixes() {
        assert!(path_matches("/jira/x", "/jira/"));
        assert!(path_matches("/jira", "/jira/"));
        assert!(!path_matches("/jiralike", "/jira/"));
        assert!(path_matches("/anything", "/"));
    }

    #[test]
    fn shipped_rules_parse() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../config/cred-broker/.config/cred-broker/config.toml");
        let r = Config::load(&path).unwrap();
        assert_eq!(r.port, 18080);
        assert!(r.auth().ends_with(".pi/agent/auth.json"));
        assert_eq!(r.github.hosts["api.github.com"], AuthScheme::Bearer);
        assert_eq!(
            r.oauth.token_command[..3],
            ["pi", "auth", "print-bearer-token"]
        );
        assert!(matches!(
            r.route("api.github.com", "/copilot_internal/v2/token"),
            Route::Block(_)
        ));
    }
}
