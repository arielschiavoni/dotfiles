//! Every parse failure here is skipped rather than reported: these caches are
//! written by the AWS CLI in an undocumented format, so an unreadable entry
//! means "no usable session", not "this tool is broken".

use std::fs;
use std::path::Path;

use jiff::Timestamp;
use serde_json::Value;

use crate::log;

/// Returns the process exit code: 0 logged in, 1 SSO token expired.
pub fn report(aws: &Path, role_arn: &str, sso_role_name: &str, sso_session: &str) -> u8 {
    let now = Timestamp::now().as_second();

    // Counted separately from the unexpired ones, because "no entry for this
    // start_url" and "the entry expired" are the two different reasons a login
    // is needed, and the log is the only place that distinction survives.
    let mut sso_remaining = None;
    let mut sso_entries = None;

    if !sso_session.is_empty() {
        let Some(url) = sso_start_url(&aws.join("config"), sso_session) else {
            println!("SSO token expired");
            log::line(&format!(
                "sso_session={sso_session} sso=no-start-url result=expired"
            ));
            return 1;
        };

        let expiries = sso_expiries(&aws.join("sso/cache"), &url);
        sso_entries = Some(expiries.len());
        match newest_valid(&expiries, now) {
            Some(expiry) => sso_remaining = Some(remaining(expiry - now)),
            None => {
                println!("SSO token expired");
                log::line(&format!(
                    "sso_session={sso_session} sso_entries={} sso=expired result=expired",
                    expiries.len()
                ));
                return 1;
            }
        }
    }

    let iam_expiries = iam_expiries(&aws.join("cli/cache"), role_arn, sso_role_name);
    let iam_remaining = newest_valid(&iam_expiries, now).map(|expiry| remaining(expiry - now));

    match (&sso_remaining, &iam_remaining) {
        (Some(sso), Some(iam)) => println!("{iam} (SSO token: {sso})"),
        (Some(sso), None) => println!("SSO token: {sso}"),
        (None, Some(iam)) => println!("{iam}"),
        (None, None) => {}
    }

    log::line(&format!(
        "sso_session={} sso_entries={} sso={} role={} iam_entries={} iam={} result=ok",
        or_dash(sso_session),
        sso_entries.map_or("-".to_string(), |n| n.to_string()),
        compact(&sso_remaining),
        or_dash(role_name(role_arn)),
        iam_expiries.len(),
        compact(&iam_remaining),
    ));

    0
}

fn remaining(seconds: i64) -> String {
    format!("{}h {}m", seconds / 3600, (seconds % 3600) / 60)
}

/// Log fields are key=value, so the space in "7h 59m" has to go.
fn compact(value: &Option<String>) -> String {
    value
        .as_deref()
        .map_or_else(|| "-".to_string(), |v| v.replace(' ', ""))
}

fn or_dash(value: &str) -> &str {
    if value.is_empty() { "-" } else { value }
}

/// `arn:aws:iam::1:role/Admin` -> `Admin`. The name is what the CLI cache is
/// matched on, and it keeps the account ID out of the log.
fn role_name(role_arn: &str) -> &str {
    role_arn.rsplit('/').next().unwrap_or_default()
}

fn newest_valid(expiries: &[i64], now: i64) -> Option<i64> {
    expiries.iter().copied().filter(|e| *e > now).max()
}

/// `sso_start_url` of the `[sso-session <name>]` block in `~/.aws/config`.
fn sso_start_url(config: &Path, session: &str) -> Option<String> {
    let text = fs::read_to_string(config).ok()?;
    let header = format!("[sso-session {session}]");
    let mut inside = false;

    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == header;
            continue;
        }
        if !inside || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=')
            && key.trim() == "sso_start_url"
        {
            return Some(value.trim().to_string());
        }
    }
    None
}

/// Expiry of every SSO token issued for `start_url`, expired ones included.
fn sso_expiries(dir: &Path, start_url: &str) -> Vec<i64> {
    json_files(dir)
        .filter_map(|entry| {
            if entry.get("startUrl")?.as_str()? != start_url {
                return None;
            }
            timestamp(entry.get("expiresAt")?.as_str()?)
        })
        .collect()
}

/// Expiry of every cached credential set belonging to the requested profile,
/// expired ones included. The CLI cache has no profile field, so a `role_arn`
/// profile is matched by role name and a profile fed straight from SSO by
/// provider.
///
/// With both empty there is nothing to match on and every entry counts, which
/// would report another profile's time. Inherited from the Python this
/// replaces, and unreachable through `aws_login.fish`: it only calls this for
/// a profile that has an `sso_session` or a `source_profile`.
fn iam_expiries(dir: &Path, role_arn: &str, sso_role_name: &str) -> Vec<i64> {
    let role = role_name(role_arn);

    json_files(dir)
        .filter_map(|entry| {
            let expiry = timestamp(entry.get("Credentials")?.get("Expiration")?.as_str()?)?;

            if !role_arn.is_empty() {
                let arn = entry
                    .get("AssumedRoleUser")
                    .and_then(|user| user.get("Arn"))
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                if !arn.contains(role) {
                    return None;
                }
            } else if !sso_role_name.is_empty()
                && entry.get("ProviderType").and_then(Value::as_str) != Some("sso")
            {
                return None;
            }

            Some(expiry)
        })
        .collect()
}

/// Every parseable `*.json` in `dir`. A missing directory yields nothing.
fn json_files(dir: &Path) -> impl Iterator<Item = Value> {
    fs::read_dir(dir)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
        .filter_map(|path| fs::read_to_string(path).ok())
        .filter_map(|text| serde_json::from_str(&text).ok())
}

/// Unix seconds. The SSO cache writes RFC 3339 with a `Z`; the CLI cache has
/// also been seen with a numeric offset, a space instead of `T`, and no zone
/// at all. jiff handles the first two; the rest are normalised here.
fn timestamp(raw: &str) -> Option<i64> {
    let mut value = raw.trim().replace(' ', "T");
    // Look past the date, so the `-` in "2026-03-17" is not read as an offset.
    if !value
        .get(10..)
        .is_some_and(|rest| rest.contains(['Z', '+', '-']))
    {
        value.push('Z');
    }
    value.parse::<Timestamp>().ok().map(Timestamp::as_second)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A scratch `~/.aws` populated with the files a test names.
    struct Aws(std::path::PathBuf);

    impl Aws {
        fn new(name: &str) -> Self {
            let dir = std::env::temp_dir().join(format!("aws-session-test-{name}"));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(dir.join("sso/cache")).unwrap();
            fs::create_dir_all(dir.join("cli/cache")).unwrap();
            fs::write(
                dir.join("config"),
                "[sso-session mine]\nsso_start_url = https://mine.example/start\n",
            )
            .unwrap();
            Self(dir)
        }

        fn write(&self, path: &str, contents: &str) -> &Self {
            fs::write(self.0.join(path), contents).unwrap();
            self
        }
    }

    impl Drop for Aws {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn at(hours: i64) -> String {
        (Timestamp::now() + jiff::SignedDuration::from_hours(hours)).to_string()
    }

    #[test]
    fn remaining_is_hours_and_minutes() {
        assert_eq!(remaining(3600 + 1800), "1h 30m");
        assert_eq!(remaining(59), "0h 0m");
    }

    #[test]
    fn log_fields_have_no_spaces_and_no_account_id() {
        assert_eq!(compact(&Some("7h 59m".to_string())), "7h59m");
        assert_eq!(compact(&None), "-");
        assert_eq!(role_name("arn:aws:iam::123456789012:role/Admin"), "Admin");
        assert_eq!(or_dash(""), "-");
    }

    #[test]
    fn timestamp_accepts_every_shape_these_caches_use() {
        let expected = 1_773_731_200;
        for raw in [
            "2026-03-17T07:06:40Z",
            "2026-03-17T07:06:40+00:00",
            "2026-03-17 07:06:40+00:00",
            "2026-03-17T07:06:40",
        ] {
            assert_eq!(timestamp(raw), Some(expected), "failed on {raw}");
        }
        assert_eq!(timestamp("not a date"), None);
        assert_eq!(timestamp(""), None);
    }

    #[test]
    fn sso_start_url_reads_only_the_named_session() {
        let aws = Aws::new("start-url");
        aws.write(
            "config",
            "[sso-session other]\nsso_start_url = https://other.example/start\n\n\
             [sso-session mine]\n# sso_start_url = https://commented.example/start\n\
             sso_start_url = https://mine.example/start\n",
        );
        let config = aws.0.join("config");
        assert_eq!(
            sso_start_url(&config, "mine").as_deref(),
            Some("https://mine.example/start")
        );
        assert_eq!(sso_start_url(&config, "absent"), None);
        assert_eq!(sso_start_url(Path::new("/nonexistent"), "mine"), None);
    }

    #[test]
    fn an_expired_token_is_counted_but_not_valid() {
        let now = Timestamp::now().as_second();
        let aws = Aws::new("sso-expired");
        aws.write(
            "sso/cache/expired.json",
            &format!(
                r#"{{"startUrl":"https://mine.example/start","expiresAt":"{}"}}"#,
                at(-1)
            ),
        );

        // Counted, so the log can say "expired" rather than "no entry".
        let expiries = sso_expiries(&aws.0.join("sso/cache"), "https://mine.example/start");
        assert_eq!(expiries.len(), 1);
        assert_eq!(newest_valid(&expiries, now), None);
    }

    #[test]
    fn another_accounts_token_is_not_even_counted() {
        let aws = Aws::new("sso-foreign");
        aws.write(
            "sso/cache/other.json",
            &format!(
                r#"{{"startUrl":"https://other.example/start","expiresAt":"{}"}}"#,
                at(8)
            ),
        )
        .write("sso/cache/registration.json", r#"{"clientId":"x"}"#);

        let expiries = sso_expiries(&aws.0.join("sso/cache"), "https://mine.example/start");
        assert!(expiries.is_empty());
    }

    #[test]
    fn the_latest_valid_sso_token_wins() {
        let now = Timestamp::now().as_second();
        let aws = Aws::new("sso-valid");
        let latest = at(8);
        aws.write(
            "sso/cache/a.json",
            &format!(
                r#"{{"startUrl":"https://mine.example/start","expiresAt":"{}"}}"#,
                at(2)
            ),
        )
        .write(
            "sso/cache/b.json",
            &format!(r#"{{"startUrl":"https://mine.example/start","expiresAt":"{latest}"}}"#),
        );

        let expiries = sso_expiries(&aws.0.join("sso/cache"), "https://mine.example/start");
        assert_eq!(newest_valid(&expiries, now), timestamp(&latest));
    }

    #[test]
    fn role_credentials_match_on_the_role_name_in_the_arn() {
        let now = Timestamp::now().as_second();
        let aws = Aws::new("iam-role");
        aws.write(
            "cli/cache/mine.json",
            &format!(
                r#"{{"Credentials":{{"Expiration":"{}"}},
                     "AssumedRoleUser":{{"Arn":"arn:aws:sts::1:assumed-role/Mine/s"}}}}"#,
                at(3)
            ),
        )
        .write("cli/cache/corrupt.json", "not json");

        let dir = aws.0.join("cli/cache");
        assert!(newest_valid(&iam_expiries(&dir, "arn:aws:iam::1:role/Mine", ""), now).is_some());
        assert!(iam_expiries(&dir, "arn:aws:iam::1:role/Other", "").is_empty());
    }

    #[test]
    fn a_direct_sso_profile_matches_on_provider_type() {
        let now = Timestamp::now().as_second();
        let aws = Aws::new("iam-sso");
        aws.write(
            "cli/cache/sso.json",
            &format!(
                r#"{{"Credentials":{{"Expiration":"{}"}},"ProviderType":"sso"}}"#,
                at(2)
            ),
        );

        let dir = aws.0.join("cli/cache");
        assert!(newest_valid(&iam_expiries(&dir, "", "MyRole"), now).is_some());
        // A role_arn profile must not be satisfied by an SSO entry.
        assert!(iam_expiries(&dir, "arn:aws:iam::1:role/Mine", "").is_empty());
    }

    #[test]
    fn an_access_key_profile_has_no_sso_clock_to_fail() {
        let aws = Aws::new("no-sso");
        assert_eq!(report(&aws.0, "", "", ""), 0);
    }
}
