//! `~/.aws/config` (and the profile names in `~/.aws/credentials`), parsed
//! directly in microseconds (`aws configure get` starts Python, ~0.3s per key).
//!
//! What aws-session, cred-broker and pi-safe need: profile names, their keys,
//! and where a profile's credentials come from (its `source_profile` chain).

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

/// `source_profile` hops followed before giving up (a cycle, most likely).
const MAX_CHAIN: usize = 8;

#[derive(Debug, Default)]
pub struct AwsConfig {
    /// `[profile x]` / `[default]` of the config file, in file order.
    profiles: Vec<(String, BTreeMap<String, String>)>,
    /// `[sso-session x]`
    sso_sessions: BTreeMap<String, BTreeMap<String, String>>,
    /// Section names of the credentials file (its values are secrets).
    credentials: Vec<String>,
}

/// Where a profile's credentials come from.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Resolved {
    /// Its own `role_arn`: an assumed role.
    pub role_arn: Option<String>,
    /// Its own `sso_role_name`: a role straight from SSO.
    pub sso_role_name: Option<String>,
    /// The `sso_session` of the first profile in the chain that has one.
    pub sso_session: Option<String>,
    /// The end of the `source_profile` chain: what `aws sso login --profile`
    /// takes for a legacy SSO profile (one without an `sso_session`).
    pub root: String,
    /// The first `region` in the chain.
    pub region: Option<String>,
}

impl AwsConfig {
    /// `<aws>/config` and `<aws>/credentials`; a missing file counts as empty.
    pub fn load(aws: &Path) -> Self {
        let mut cfg = Self::parse(&fs::read_to_string(aws.join("config")).unwrap_or_default());
        let creds = fs::read_to_string(aws.join("credentials")).unwrap_or_default();
        cfg.credentials = sections(&creds).into_iter().map(|(n, _)| n).collect();
        cfg
    }

    pub fn parse(text: &str) -> Self {
        let mut cfg = Self::default();
        for (header, keys) in sections(text) {
            if let Some(name) = header.strip_prefix("profile ") {
                cfg.profiles.push((name.trim().to_string(), keys));
            } else if header == "default" {
                cfg.profiles.push((header, keys));
            } else if let Some(name) = header.strip_prefix("sso-session ") {
                cfg.sso_sessions.insert(name.trim().to_string(), keys);
            }
        }
        cfg
    }

    /// Every profile, as `aws configure list-profiles` has them: the config
    /// file's in order, then those only in the credentials file.
    pub fn profiles(&self) -> Vec<String> {
        let mut out: Vec<String> = self.profiles.iter().map(|(n, _)| n.clone()).collect();
        for name in &self.credentials {
            if !out.contains(name) {
                out.push(name.clone());
            }
        }
        out
    }

    pub fn has_profile(&self, name: &str) -> bool {
        self.profiles.iter().any(|(n, _)| n == name) || self.credentials.iter().any(|n| n == name)
    }

    /// A key of a profile in the config file.
    pub fn get(&self, profile: &str, key: &str) -> Option<&str> {
        self.profiles
            .iter()
            .find(|(n, _)| n == profile)
            .and_then(|(_, keys)| keys.get(key))
            .map(String::as_str)
    }

    /// `sso_start_url` of an `[sso-session]`.
    pub fn sso_start_url(&self, session: &str) -> Option<&str> {
        self.sso_sessions
            .get(session)?
            .get("sso_start_url")
            .map(String::as_str)
    }

    /// Follows the `source_profile` chain of `profile`.
    pub fn resolve(&self, profile: &str) -> Resolved {
        let own = |key| self.get(profile, key).map(str::to_string);
        let mut r = Resolved {
            role_arn: own("role_arn"),
            sso_role_name: own("sso_role_name"),
            root: profile.to_string(),
            ..Resolved::default()
        };
        let mut current = profile.to_string();
        for _ in 0..MAX_CHAIN {
            if r.sso_session.is_none() {
                r.sso_session = self.get(&current, "sso_session").map(str::to_string);
            }
            if r.region.is_none() {
                r.region = self.get(&current, "region").map(str::to_string);
            }
            r.root = current.clone();
            match self.get(&current, "source_profile") {
                Some(next) if next != current => current = next.to_string(),
                _ => break,
            }
        }
        r
    }
}

/// `[header]` -> keys, in file order. Comments, and the indented lines of
/// nested values (`s3 =` followed by `  max_concurrent_requests = 20`), are
/// skipped.
fn sections(text: &str) -> Vec<(String, BTreeMap<String, String>)> {
    let mut out: Vec<(String, BTreeMap<String, String>)> = Vec::new();
    for raw in text.lines() {
        if raw.starts_with([' ', '\t']) {
            continue;
        }
        let line = raw.trim();
        if line.is_empty() || line.starts_with(['#', ';']) {
            continue;
        }
        if let Some(header) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            out.push((header.trim().to_string(), BTreeMap::new()));
        } else if let (Some((key, value)), Some((_, keys))) = (line.split_once('='), out.last_mut())
        {
            keys.insert(key.trim().to_string(), value.trim().to_string());
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONFIG: &str = "\
[sso-session corp]
sso_start_url = https://corp.example/start/#
sso_region = eu-central-1

[profile app.dev.admin]
sso_session = corp
sso_role_name = admin
region = eu-west-1

# [profile commented]
# sso_session = corp

[profile app.dev.agent]
role_arn = arn:aws:iam::1:role/ai-readonly
source_profile = app.dev.admin
s3 =
  max_concurrent_requests = 20

[default]
region = us-east-1

[profile loop]
source_profile = loop
";

    #[test]
    fn lists_profiles_in_file_order_without_comments() {
        let mut cfg = AwsConfig::parse(CONFIG);
        cfg.credentials = vec!["keys".into(), "default".into()];
        assert_eq!(
            cfg.profiles(),
            ["app.dev.admin", "app.dev.agent", "default", "loop", "keys"]
        );
        assert!(cfg.has_profile("keys"));
        assert!(!cfg.has_profile("commented"));
    }

    #[test]
    fn nested_values_are_not_keys() {
        let cfg = AwsConfig::parse(CONFIG);
        assert_eq!(cfg.get("app.dev.agent", "s3"), Some(""));
        assert_eq!(cfg.get("app.dev.agent", "max_concurrent_requests"), None);
    }

    #[test]
    fn resolves_a_role_through_its_source_profile() {
        let cfg = AwsConfig::parse(CONFIG);
        assert_eq!(
            cfg.resolve("app.dev.agent"),
            Resolved {
                role_arn: Some("arn:aws:iam::1:role/ai-readonly".into()),
                sso_role_name: None,
                sso_session: Some("corp".into()),
                root: "app.dev.admin".into(),
                region: Some("eu-west-1".into()),
            }
        );
        assert_eq!(
            cfg.sso_start_url("corp"),
            Some("https://corp.example/start/#")
        );
    }

    #[test]
    fn a_cycle_or_an_unknown_profile_ends_the_chain() {
        let cfg = AwsConfig::parse(CONFIG);
        assert_eq!(cfg.resolve("loop").root, "loop");
        let r = cfg.resolve("absent");
        assert_eq!((r.root.as_str(), r.sso_session), ("absent", None));
    }
}
