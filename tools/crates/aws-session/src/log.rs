//! `$XDG_STATE_HOME/aws-session.log`, defaulting to `~/.local/state/...` per
//! the XDG Base Directory spec - the same place and shape as
//! git-credential-multiaccount's log, for the same reason: this is a one-shot
//! process invoked by a fish function, with no supervisor to redirect stderr
//! to.
//!
//! Unlike that crate, the timestamp costs no subprocess. It shells out to
//! `date` to avoid taking on a time dependency; this crate already has jiff.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;

/// Appends one timestamped line. Silently does nothing if the log cannot be
/// opened: logging must never change what `aws_login` is told.
pub fn line(msg: &str) {
    let Some(path) = path() else { return };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    // 0600 at creation, not a chmod afterwards: role and sso-session names are
    // the same class of information as ~/.aws/config, and mode() is ignored
    // for a file that already exists, so there is no window to widen.
    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(&path)
    {
        let now = jiff::Zoned::now();
        let _ = writeln!(file, "[{}] {msg}", now.strftime("%Y-%m-%d %H:%M:%S"));
    }
}

fn path() -> Option<PathBuf> {
    let base = match std::env::var_os("XDG_STATE_HOME") {
        Some(state) => PathBuf::from(state),
        None => PathBuf::from(std::env::var_os("HOME")?).join(".local/state"),
    };
    Some(base.join("aws-session.log"))
}
