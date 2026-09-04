//! git-credential-multiaccount — routes git HTTPS credentials by the remote
//! path's first segment (org/group), so different orgs on the same host can
//! use different personal access tokens without SSH.
//!
//! ## Git credential protocol
//!
//! Set as git's global (and only) credential helper via `[credential] helper
//! = multiaccount` plus `useHttpPath = true`, git invokes this binary as:
//!
//!   git-credential-multiaccount get     (stdin has protocol=/host=/path=...)
//!   git-credential-multiaccount store   (no-op: gopass is the only store)
//!   git-credential-multiaccount erase   (no-op)
//!
//! `path` is only sent when `useHttpPath = true`; its first segment
//! (`<org>/<repo>.git`) is the token lookup key.
//!
//! ## Shell usage
//!
//!   git-credential-multiaccount token <org>
//!
//! Prints the resolved token to stdout. This lets other tools (the fish PWD
//! hook that exports $GITHUB_TOKEN) share this lookup instead of
//! reimplementing the gopass/cache logic below.
//!
//! ## Token resolution
//!
//! `personal/dotfiles/github-tokens/<key>` in gopass, falling back to
//! `personal/dotfiles/github-tokens/default` when that key has no secret.
//! Results are cached at `~/.cache/gopass/github-token-<key>` so a repeated
//! lookup for the same key does not re-invoke gopass (and its GPG prompt)
//! every time. `fish_reload` clears that cache directory.
//!
//! ## Log
//!
//! Every request is logged (org requested, cache hit/miss, which secret
//! answered, errors) to `$XDG_STATE_HOME/git-credential-multiaccount.log`
//! (default `~/.local/state/...`) — never the token itself. This is a plain
//! file the binary appends to directly, not a daemon log: unlike
//! `devbox-bridge`, there is no supervisor to redirect stderr for a one-shot
//! process invoked by git or fish on every request.

use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("get") => cmd_get(),
        Some(op @ ("store" | "erase")) => {
            log(&format!("{op} noop"));
            ExitCode::SUCCESS
        }
        Some("token") => match args.next() {
            Some(key) => cmd_token(&key),
            None => {
                eprintln!("usage: git-credential-multiaccount token <key>");
                ExitCode::FAILURE
            }
        },
        _ => {
            eprintln!("usage: git-credential-multiaccount <get|store|erase|token <key>>");
            ExitCode::FAILURE
        }
    }
}

fn cmd_get() -> ExitCode {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        return ExitCode::FAILURE;
    }

    let key = input
        .lines()
        .find_map(|line| line.strip_prefix("path="))
        .and_then(org_from_path);
    let Some(key) = key else {
        log("get error=no-path");
        return ExitCode::SUCCESS; // no path sent: nothing we can route on
    };

    match resolve_token("get", &key) {
        Some(token) => {
            println!("username=x-access-token");
            println!("password={token}");
            ExitCode::SUCCESS
        }
        None => {
            eprintln!(
                "git-credential-multiaccount: no token for '{key}' or 'default' \
                 (gopass insert personal/dotfiles/github-tokens/{key})"
            );
            // Empty stdout, exit 0: let git fall through to its own prompt
            // instead of a confusing hard failure.
            ExitCode::SUCCESS
        }
    }
}

fn cmd_token(key: &str) -> ExitCode {
    match resolve_token("token", key) {
        Some(token) => {
            print!("{token}");
            ExitCode::SUCCESS
        }
        None => ExitCode::FAILURE,
    }
}

/// First non-empty path segment: `"ASG-SONG/repo.git"` -> `"ASG-SONG"`.
fn org_from_path(path: &str) -> Option<String> {
    let org = path.trim_start_matches('/').split('/').next()?;
    if org.is_empty() {
        return None;
    }
    Some(org.to_string())
}

/// gopass lookup with a fallback to the `default` key, cached on disk.
/// `op` (`"get"` or `"token"`) is only used to label the log line.
fn resolve_token(op: &str, key: &str) -> Option<String> {
    let cache_file = cache_path(key)?;
    if let Ok(cached) = fs::read_to_string(&cache_file)
        && !cached.is_empty()
    {
        log(&format!("{op} org={key} cache=hit"));
        return Some(cached);
    }

    if let Some(token) = gopass_show(key) {
        write_cache(&cache_file, &token);
        log(&format!("{op} org={key} cache=miss source=org"));
        return Some(token);
    }

    if key != "default"
        && let Some(token) = gopass_show("default")
    {
        write_cache(&cache_file, &token);
        log(&format!("{op} org={key} cache=miss source=default"));
        return Some(token);
    }

    log(&format!("{op} org={key} cache=miss error=no-token"));
    None
}

fn write_cache(cache_file: &Path, token: &str) {
    if let Some(parent) = cache_file.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::write(cache_file, token);
}

fn cache_path(key: &str) -> Option<PathBuf> {
    let home = env::var_os("HOME")?;
    Some(
        PathBuf::from(home)
            .join(".cache/gopass")
            .join(format!("github-token-{key}")),
    )
}

/// `$XDG_STATE_HOME/git-credential-multiaccount.log`, defaulting to
/// `~/.local/state/...` per the XDG Base Directory spec. Works unchanged on
/// both the macOS host and the Ubuntu devbox guest, unlike a macOS-only path
/// such as `~/Library/Logs`.
fn log_path() -> Option<PathBuf> {
    let home = env::var_os("HOME")?;
    let base = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(home).join(".local/state"));
    Some(base.join("git-credential-multiaccount.log"))
}

/// Timestamped line appended to `log_path()`. Never logs a token - only the
/// requested org, cache hit/miss, which secret answered, and errors. Silently
/// does nothing if the log can't be opened; logging must never affect
/// whether a credential resolves.
fn log(msg: &str) {
    let Some(path) = log_path() else { return };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(f, "[{}] {msg}", now());
    }
}

/// `date`'s own local-time formatting - readable in the log without adding a
/// time-formatting dependency. Falls back to a placeholder if `date` is
/// somehow unavailable.
fn now() -> String {
    Command::new("date")
        .arg("+%Y-%m-%d %H:%M:%S")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "?".to_string())
}

fn gopass_show(key: &str) -> Option<String> {
    let output = Command::new("gopass")
        .args([
            "show",
            "-o",
            &format!("personal/dotfiles/github-tokens/{key}"),
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let token = String::from_utf8(output.stdout).ok()?;
    let token = token.trim().to_string();
    (!token.is_empty()).then_some(token)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn org_from_path_takes_first_segment() {
        assert_eq!(
            org_from_path("ASG-SONG/repo.git").as_deref(),
            Some("ASG-SONG")
        );
    }

    #[test]
    fn org_from_path_strips_leading_slash() {
        assert_eq!(org_from_path("/oneaudi/repo").as_deref(), Some("oneaudi"));
    }

    #[test]
    fn org_from_path_rejects_empty() {
        assert_eq!(org_from_path(""), None);
        assert_eq!(org_from_path("/"), None);
    }
}
