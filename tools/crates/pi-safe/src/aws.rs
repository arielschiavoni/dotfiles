//! AWS inside the sandbox, from cred-broker.
//!
//! The sandbox's ~/.aws/config lists the profiles the broker serves
//! (`aws_profiles` of `cred-broker status --json`), each with a
//! `credential_process` that is this binary: `__aws-credentials <port>
//! <profile>` asks `http://cred-broker/aws/<profile>` and prints the answer.
//! The AWS CLI and SDKs run it whenever the credentials they hold are about
//! to expire, so a session outlives the 1h of a chained role.
//!
//! The rest of the real ~/.aws stays outside, with its SSO token, which makes
//! credentials for every profile.

use std::fmt::Write as _;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::process::ExitCode;
use std::time::Duration;

use aws_session::config::AwsConfig;
use serde_json::Value;

/// What the sandbox's credential_process runs (the binary is mounted at
/// `probe::SANDBOX_PATH`).
pub const ARG: &str = "__aws-credentials";

/// The broker may wait for an SSO login to be approved (5 min), with a
/// credentials fetch before and after it.
const READ_TIMEOUT: Duration = Duration::from_secs(8 * 60);

/// The sandbox's ~/.aws/config: `profiles`, each fed by the broker at `port`,
/// with the region of the real profile (from its `source_profile` chain).
pub fn config_file(profiles: &[String], port: u16, real: &AwsConfig, exe: &str) -> String {
    let mut out = String::from(
        "# Written by pi-safe: the AWS profiles cred-broker serves ([aws] in\n\
         # ~/.config/cred-broker/config.toml). Credentials come from the broker.\n",
    );
    for p in profiles {
        let _ = write!(
            out,
            "\n[profile {p}]\ncredential_process = {exe} {ARG} {port} {p}\n"
        );
        if let Some(region) = real.resolve(p).region {
            let _ = writeln!(out, "region = {region}");
        }
    }
    out
}

/// `__aws-credentials <port> <profile>`: the broker's answer on stdout, or
/// its reason on stderr (the AWS CLI shows it).
pub fn run(args: &[String]) -> ExitCode {
    let (Some(port), Some(profile)) = (args.first().and_then(|p| p.parse().ok()), args.get(1))
    else {
        eprintln!("usage: pi-safe {ARG} <port> <profile>");
        return ExitCode::from(2);
    };
    match get(port, profile) {
        Ok(json) => {
            println!("{json}");
            ExitCode::SUCCESS
        }
        Err(why) => {
            eprintln!("{why}");
            ExitCode::FAILURE
        }
    }
}

fn get(port: u16, profile: &str) -> Result<String, String> {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let mut s = TcpStream::connect_timeout(&addr, Duration::from_secs(3))
        .map_err(|e| format!("cred-broker is not reachable on 127.0.0.1:{port}: {e}"))?;
    let _ = s.set_read_timeout(Some(READ_TIMEOUT));
    write!(
        s,
        "GET http://cred-broker/aws/{profile} HTTP/1.1\r\nHost: cred-broker\r\nConnection: close\r\n\r\n"
    )
    .map_err(|e| format!("cred-broker: {e}"))?;
    let mut resp = String::new();
    s.read_to_string(&mut resp)
        .map_err(|e| format!("cred-broker: no answer: {e}"))?;
    parse(&resp)
}

/// The body of a 200; else the broker's `message`.
fn parse(resp: &str) -> Result<String, String> {
    let (head, body) = resp
        .split_once("\r\n\r\n")
        .ok_or("cred-broker: bad response")?;
    if head.starts_with("HTTP/1.1 200") {
        return Ok(body.trim().to_string());
    }
    let message = serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|v| v.get("message")?.as_str().map(str::to_string))
        .unwrap_or_else(|| head.lines().next().unwrap_or_default().to_string());
    Err(message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_has_only_the_served_profiles_and_their_region() {
        let real = AwsConfig::parse(
            "[profile app.admin]\nsso_session = corp\nregion = eu-central-1\n\
             [profile app.agent]\nrole_arn = arn:aws:iam::1:role/ai\nsource_profile = app.admin\n\
             [profile b.agent]\n",
        );
        let text = config_file(
            &["app.agent".into(), "b.agent".into()],
            18080,
            &real,
            "/run/pi-safe",
        );
        assert!(text.contains(
            "[profile app.agent]\ncredential_process = /run/pi-safe __aws-credentials 18080 app.agent\nregion = eu-central-1\n"
        ), "{text}");
        assert!(
            text.contains("[profile b.agent]\ncredential_process"),
            "{text}"
        );
        for leak in ["app.admin", "sso_session", "role_arn"] {
            assert!(!text.contains(leak), "{leak} in {text}");
        }
    }

    #[test]
    fn parses_the_broker_answer() {
        let ok = "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\n{\"Version\":1}\n";
        assert_eq!(parse(ok).unwrap(), "{\"Version\":1}");
        let err =
            "HTTP/1.1 502 Bad Gateway\r\n\r\n{\"message\":\"cred-broker: AWS SSO login failed\"}";
        assert_eq!(parse(err).unwrap_err(), "cred-broker: AWS SSO login failed");
        assert_eq!(
            parse("HTTP/1.1 404 Not Found\r\n\r\n").unwrap_err(),
            "HTTP/1.1 404 Not Found"
        );
    }
}
