//! aws-session — AWS SSO logins, for `aws_login.fish` and cred-broker.
//!
//! Two clocks have to agree before an AWS call succeeds, and they expire at
//! different times:
//!
//!   ~/.aws/sso/cache   the SSO access token (~1h, renewed silently with its
//!                      refresh token until the SSO session ends, ~8h)
//!   ~/.aws/cli/cache   the assumed-role credentials (1-4h; 1h when chained)
//!
//! Subcommands, exit 0 ok, 1 an expected "no" (login needed, nothing
//! chosen), 2 a failure:
//!
//!   status <profile>        time left on both clocks
//!   pick [--filter GLOB]    choose a profile with fzf, print it
//!   ensure <profile>        usable credentials, logging in when needed
//!   credentials <profile>   credentials as JSON, for credential_process
//!   login <profile>         `aws sso login` for the profile's SSO session
//!
//! "Login needed" is decided by asking the CLI for credentials first: a login
//! is needed when that fails and the SSO access token has expired. Any other
//! failure (a denied role, the network) is reported with the CLI's reason.
//!
//! ## Log
//!
//! `status` appends one key=value line to `$XDG_STATE_HOME/aws-session.log`
//! (default `~/.local/state/...`), see session.rs.

use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};

use aws_session::config::AwsConfig;
use aws_session::{glob, session};
use clap::{Parser, Subcommand};

/// AWS SSO logins: time left, pick a profile, log in, credentials.
#[derive(Parser)]
#[command(name = "aws-session")]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Time left on a profile's login (exit 1: SSO login needed)
    Status { profile: String },
    /// Choose a profile with fzf and print its name (exit 1: none chosen)
    Pick {
        /// Only profiles matching GLOB (`*` any characters; repeatable)
        #[arg(long, value_name = "GLOB")]
        filter: Vec<String>,
    },
    /// Make a profile usable: log in to its SSO session if needed
    Ensure { profile: String },
    /// Credentials of a profile in credential_process format (exit 1: SSO
    /// login needed)
    Credentials { profile: String },
    /// Log in to the profile's SSO session (`aws sso login`)
    Login {
        profile: String,
        /// The device code flow (`--use-device-code`): the browser page shows
        /// a code to compare
        #[arg(long)]
        device_code: bool,
        /// Show a tmux message that a login waits for approval (for a login
        /// started in the background, by cred-broker)
        #[arg(long)]
        notify: bool,
    },
}

/// What asking the CLI for credentials gave.
enum Creds {
    Ok(String),
    LoginNeeded(String),
    Failed(String),
}

fn main() -> ExitCode {
    let Some(home) = std::env::var_os("HOME") else {
        eprintln!("aws-session: HOME is not set");
        return ExitCode::from(2);
    };
    let aws = PathBuf::from(home).join(".aws");
    let cfg = AwsConfig::load(&aws);

    let code = match Cli::parse().command {
        Cmd::Status { profile } => {
            let s = session::status(&aws, &cfg, &cfg.resolve(&profile));
            println!("{}", s.line);
            s.code
        }
        Cmd::Pick { filter } => pick(&cfg, &filter),
        Cmd::Ensure { profile } => ensure(&aws, &cfg, &profile),
        Cmd::Credentials { profile } => match credentials(&aws, &cfg, &profile) {
            Creds::Ok(json) => {
                println!("{json}");
                0
            }
            Creds::LoginNeeded(why) => fail(1, &why),
            Creds::Failed(why) => fail(2, &why),
        },
        Cmd::Login {
            profile,
            device_code,
            notify,
        } => match login(&cfg, &profile, device_code, notify) {
            Ok(()) => 0,
            Err(why) => fail(2, &why),
        },
    };
    ExitCode::from(code)
}

fn fail(code: u8, why: &str) -> u8 {
    eprintln!("aws-session: {why}");
    code
}

/// fzf over the profiles, the chosen one on stdout.
fn pick(cfg: &AwsConfig, filter: &[String]) -> u8 {
    let names: Vec<String> = cfg
        .profiles()
        .into_iter()
        .filter(|n| filter.is_empty() || glob::any(filter, n))
        .collect();
    if names.is_empty() {
        return fail(1, "no AWS profiles to choose from");
    }
    let child = Command::new("fzf")
        .args(["--prompt", "Choose active AWS profile: "])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn();
    let mut child = match child {
        Ok(c) => c,
        Err(e) => return fail(2, &format!("cannot run fzf: {e}")),
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(format!("{}\n", names.join("\n")).as_bytes());
    }
    let chosen = child
        .wait_with_output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();
    if chosen.is_empty() {
        eprintln!("No profile selected.");
        return 1;
    }
    println!("{chosen}");
    0
}

/// `aws_login.fish`: credentials, else a login and credentials again; then
/// the time left.
fn ensure(aws: &Path, cfg: &AwsConfig, profile: &str) -> u8 {
    match credentials(aws, cfg, profile) {
        Creds::Ok(_) => {}
        Creds::LoginNeeded(why) => {
            println!("{why}, logging in...");
            if let Err(why) = login(cfg, profile, false, false) {
                return fail(2, &why);
            }
            match credentials(aws, cfg, profile) {
                Creds::Ok(_) => {}
                Creds::LoginNeeded(why) | Creds::Failed(why) => return fail(2, &why),
            }
        }
        Creds::Failed(why) => return fail(2, &why),
    }
    let s = session::status(aws, cfg, &cfg.resolve(profile));
    match s.line.as_str() {
        "" => println!("Session valid."),
        left => println!("Session valid, expires in {left}."),
    }
    0
}

/// `aws configure export-credentials`: renews the SSO token and the role
/// credentials as needed, and caches them in ~/.aws.
fn credentials(aws: &Path, cfg: &AwsConfig, profile: &str) -> Creds {
    if !cfg.has_profile(profile) {
        return Creds::Failed(format!("no profile '{profile}' in ~/.aws/config"));
    }
    let out = Command::new("aws")
        .args(["configure", "export-credentials", "--profile", profile])
        .args(["--format", "process"])
        .stdin(Stdio::null())
        .output();
    let out = match out {
        Ok(o) => o,
        Err(e) => return Creds::Failed(format!("cannot run aws: {e}")),
    };
    if out.status.success() {
        return Creds::Ok(String::from_utf8_lossy(&out.stdout).trim().to_string());
    }
    match cfg.resolve(profile).sso_session {
        Some(s) if !session::sso_valid(aws, cfg, &s) => {
            Creds::LoginNeeded(format!("AWS SSO login needed (sso-session {s})"))
        }
        _ => Creds::Failed(last_line(&out.stderr)),
    }
}

/// `aws sso login` for the SSO session of `profile` (or its root profile,
/// for a legacy SSO profile without an `sso_session`).
fn login(cfg: &AwsConfig, profile: &str, device_code: bool, notify: bool) -> Result<(), String> {
    let r = cfg.resolve(profile);
    let mut cmd = Command::new("aws");
    cmd.args(["sso", "login"]);
    match &r.sso_session {
        Some(s) => cmd.args(["--sso-session", s]),
        None if cfg.get(&r.root, "sso_start_url").is_some() => cmd.args(["--profile", &r.root]),
        None => return Err(format!("'{profile}' is not an SSO profile")),
    };
    if device_code {
        cmd.arg("--use-device-code");
    }

    let status = if notify {
        // in the background: the code goes to a tmux message, the CLI's
        // output to stderr (the caller's log)
        if !device_code {
            tmux_message(&format!(
                "AWS SSO login for {profile}: approve it in the browser"
            ));
        }
        let mut child = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| format!("cannot run aws: {e}"))?;
        if let Some(out) = child.stdout.take() {
            let mut shown = false;
            for line in BufReader::new(out).lines().map_while(Result::ok) {
                eprintln!("{line}");
                if !shown && let Some(code) = user_code(&line) {
                    tmux_message(&format!(
                        "AWS SSO login for {profile}: approve code {code} in the browser"
                    ));
                    shown = true;
                }
            }
        }
        child.wait()
    } else {
        cmd.status()
    };
    match status {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(format!("aws sso login exited {}", s.code().unwrap_or(-1))),
        Err(e) => Err(format!("cannot run aws: {e}")),
    }
}

/// The device code the CLI prints on a line of its own: `ABCD-EFGH`.
fn user_code(line: &str) -> Option<&str> {
    let code = line.trim();
    let ok = code.len() == 9
        && code.char_indices().all(|(i, c)| match i {
            4 => c == '-',
            _ => c.is_ascii_uppercase() || c.is_ascii_digit(),
        });
    ok.then_some(code)
}

/// A tmux message, when tmux runs (best effort).
fn tmux_message(text: &str) {
    let _ = Command::new("tmux")
        .args(["display-message", "-d", "60000", text])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn last_line(stderr: &[u8]) -> String {
    let text = String::from_utf8_lossy(stderr);
    let line = text.trim().lines().last().unwrap_or("aws failed").trim();
    line.chars().take(300).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_device_code_line() {
        assert_eq!(user_code("XMSK-NGNL"), Some("XMSK-NGNL"));
        assert_eq!(user_code("  AB12-CD34 \n"), Some("AB12-CD34"));
        for line in [
            "Then enter the code:",
            "https://x/device?user_code=XMSK-NGNL",
            "xmsk-ngnl",
            "XMSKNNGNL",
        ] {
            assert_eq!(user_code(line), None, "{line}");
        }
    }

    #[test]
    fn last_stderr_line_is_the_reason() {
        assert_eq!(last_line(b"\nfirst\nthe reason\n"), "the reason");
        assert_eq!(last_line(b""), "aws failed");
    }
}
