//! aws-session — how much time is left on the current AWS login.
//!
//! Two clocks have to agree before an AWS call succeeds, and they expire at
//! different times:
//!
//!   ~/.aws/sso/cache   the SSO access token (~8h), matched by sso_start_url
//!   ~/.aws/cli/cache   the assumed-role credentials (1-4h), matched by role
//!
//!   aws-session <role_arn> <sso_role_name> <sso_session>    args may be empty
//!
//! Exit 0 means logged in, with the remaining time on stdout. Exit 1 means the
//! SSO token is missing or expired and the caller should run `aws sso login`.
//! `functions/aws_login.fish` branches on both.
//!
//! ## Log
//!
//! One key=value line per invocation to `$XDG_STATE_HOME/aws-session.log`
//! (default `~/.local/state/...`) — which profile was asked about, how many
//! cache entries matched it, and what was left on each clock:
//!
//!   sso_session=x sso_entries=1 sso=7h59m role=Admin iam_entries=1 iam=2h30m result=ok
//!   sso_session=x sso_entries=1 sso=expired result=expired
//!   sso_session=x sso=no-start-url result=expired
//!
//! `sso_entries` is what separates "no cached token for this start URL" from
//! "the token expired" — stdout says only "SSO token expired" for both. Roles
//! are logged by name, not ARN, so no account ID lands in the file.

mod log;
mod session;

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let Some(home) = env::var_os("HOME") else {
        eprintln!("aws-session: HOME is not set");
        return ExitCode::from(2);
    };

    let args: Vec<String> = env::args().skip(1).collect();
    let arg = |i: usize| args.get(i).map(String::as_str).unwrap_or_default();

    ExitCode::from(session::report(
        &PathBuf::from(home).join(".aws"),
        arg(0),
        arg(1),
        arg(2),
    ))
}
