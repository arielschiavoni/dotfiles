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

use std::io::Write;
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
    Login { profile: String },
}

/// The result of asking the AWS CLI for a profile's credentials.
enum Creds {
    /// The credentials, as credential_process JSON.
    Ok(String),
    /// The SSO token has expired: the user has to log in again.
    LoginNeeded(String),
    /// Any other error, with the CLI's message.
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
        Cmd::Login { profile } => match login(&cfg, &profile) {
            Ok(()) => 0,
            Err(why) => fail(2, &why),
        },
    };
    ExitCode::from(code)
}

/// Prints the error to stderr and returns `code`, the exit code to use.
fn fail(code: u8, why: &str) -> u8 {
    eprintln!("aws-session: {why}");
    code
}

/// Lets the user choose a profile from ~/.aws/config in fzf and prints its
/// name. With `filter`, only the profiles that match one of the globs are
/// listed. Returns 1 when no profile was chosen.
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

/// Makes sure a profile can be used, and prints how long the session lasts.
/// Used by `aws_login.fish`.
///
/// It gets the profile's credentials. If that fails because the SSO token has
/// expired, it logs in and tries again.
///
/// It also logs in when the credentials work but the SSO token has expired.
/// The AWS CLI can still return credentials it cached earlier, but the AWS
/// SDKs (used by Node scripts, Terraform, ...) need a valid SSO token.
fn ensure(aws: &Path, cfg: &AwsConfig, profile: &str) -> u8 {
    let login_needed = match credentials(aws, cfg, profile) {
        Creds::Ok(_) => match cfg.resolve(profile).sso_session {
            Some(s) if !session::sso_valid(aws, cfg, &s) => {
                Some(format!("AWS SSO token expired (sso-session {s})"))
            }
            _ => None,
        },
        Creds::LoginNeeded(why) => Some(why),
        Creds::Failed(why) => return fail(2, &why),
    };
    match login_needed {
        None => {}
        Some(why) => {
            println!("{why}, logging in...");
            if let Err(why) = login(cfg, profile) {
                return fail(2, &why);
            }
            match credentials(aws, cfg, profile) {
                Creds::Ok(_) => {}
                Creds::LoginNeeded(why) | Creds::Failed(why) => return fail(2, &why),
            }
        }
    }
    let s = session::status(aws, cfg, &cfg.resolve(profile));
    if s.code != 0 {
        return fail(2, &s.line);
    }
    match s.line.as_str() {
        "" => println!("Session valid."),
        left => println!("Session valid, expires in {left}."),
    }
    0
}

/// Gets the credentials of a profile with `aws configure export-credentials`.
/// The CLI renews expired credentials by itself while the SSO session lasts.
///
/// When the CLI fails, the result is `LoginNeeded` if the SSO token has
/// expired, and `Failed` with the CLI's error message otherwise.
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

/// Logs in to the SSO session of a profile with `aws sso login`, which opens
/// the browser. Older SSO profiles without an `sso_session` are logged in
/// with `--profile` instead.
fn login(cfg: &AwsConfig, profile: &str) -> Result<(), String> {
    let r = cfg.resolve(profile);
    let mut cmd = Command::new("aws");
    cmd.args(["sso", "login"]);
    match &r.sso_session {
        Some(s) => cmd.args(["--sso-session", s]),
        None if cfg.get(&r.root, "sso_start_url").is_some() => cmd.args(["--profile", &r.root]),
        None => return Err(format!("'{profile}' is not an SSO profile")),
    };
    match cmd.status() {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(format!("aws sso login exited {}", s.code().unwrap_or(-1))),
        Err(e) => Err(format!("cannot run aws: {e}")),
    }
}

/// Returns the last line of the CLI's error output, which says what went
/// wrong. Long lines are cut to 300 characters.
fn last_line(stderr: &[u8]) -> String {
    let text = String::from_utf8_lossy(stderr);
    let line = text.trim().lines().last().unwrap_or("aws failed").trim();
    line.chars().take(300).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn last_stderr_line_is_the_reason() {
        assert_eq!(last_line(b"\nfirst\nthe reason\n"), "the reason");
        assert_eq!(last_line(b""), "aws failed");
    }
}
