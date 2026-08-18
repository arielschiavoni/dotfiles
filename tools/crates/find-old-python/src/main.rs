//! find-old-python — locate Python installations below a version threshold.
//!
//! This is a corporate-compliance tool: the allowed Python is 3.13.x, so
//! anything older is a violation that must be reported and, where possible,
//! removed.
//!
//! ## How it works
//!
//! A parallel directory walk (the `ignore` crate — the same walker that powers
//! `fd` and `ripgrep`) visits a fixed set of roots. Any file or symlink whose
//! *name* looks like `python`, `python3`, `python3.11`, … is a candidate.
//!
//! Candidates are classified **inside the walker's callback**, on whatever
//! worker thread found them. That matters: the walk is ~97% of the runtime, so
//! running `python --version` inline hides that cost underneath the walk
//! instead of adding a second serial phase after it. Only ~100 of several
//! million visited entries are candidates, so briefly blocking a walker thread
//! is irrelevant.
//!
//! Results travel back to the main thread over an `mpsc` channel
//! (multi-producer, single-consumer) — exactly the shape of "many walker
//! threads, one collector", and it is in the standard library, so no extra
//! dependency and no shared mutex for the result list.
//!
//! ## Rust notes for the reader
//!
//! - `&str` is a borrowed string slice, `String` is owned. `&Path` / `PathBuf`
//!   are the same split for filesystem paths.
//! - `Option<T>` is "maybe a T" (no `null`). `Result<T, E>` is "T or an error".
//! - `?` after a fallible call returns the error to the caller — it is the
//!   equivalent of rethrowing in a `try`/`catch` language.
//! - `Arc<T>` is a thread-safe reference-counted pointer: it lets several
//!   threads share one value. `Mutex<T>` guards mutation of that shared value.

use std::collections::HashMap;
use std::ffi::OsStr;
use std::fs;
use std::io::{self, BufWriter, IsTerminal, Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::time::{Duration, Instant};

use clap::Parser;
use ignore::{WalkBuilder, WalkState};

/// Little-endian magic for a 64-bit Mach-O file (`MH_MAGIC_64`), as it appears
/// on disk on arm64 and x86_64.
const MACHO_MAGIC_64_LE: [u8; 4] = [0xcf, 0xfa, 0xed, 0xfe];

/// `MH_DYLIB` — the Mach-O header's `filetype` value for a shared library.
const MACHO_TYPE_DYLIB: u32 = 0x6;

// ─────────────────────────────────────────────────────────────────────────────
// CLI
// ─────────────────────────────────────────────────────────────────────────────

/// clap's `derive` feature turns this struct into a full argument parser: each
/// field becomes a flag, and the doc comments become the `--help` text.
#[derive(Parser, Debug)]
#[command(
    name = "find-old-python",
    version,
    about = "Scan macOS for Python installations below a version threshold",
    long_about = None,
    after_help = "EXIT CODES\n  \
        0   Compliant — no violations found\n  \
        1   Violations found (or remaining after --clean)\n  \
        2   Tool error"
)]
struct Cli {
    /// Version threshold, exclusive. Anything below this is a violation.
    #[arg(long, value_name = "VERSION", default_value = "3.13")]
    below: String,

    /// Remove violations that are safe to delete, plus broken symlinks.
    /// Package-manager-owned, app-bundled and MDM-managed Pythons are never
    /// deleted — they are reported with the correct remediation instead.
    #[arg(long)]
    clean: bool,

    /// Skip confirmation prompts. Use with --clean in CI.
    #[arg(long)]
    yes: bool,

    /// Also list non-executable matches and shared libraries.
    #[arg(long)]
    verbose: bool,

    /// Override the default scan roots. Repeatable.
    #[arg(long, value_name = "PATH")]
    root: Vec<PathBuf>,

    /// Skip any path containing this substring. Repeatable.
    #[arg(long, value_name = "SUBSTRING")]
    exclude: Vec<String>,

    /// Scan all of $HOME instead of the targeted subdirectories used by
    /// default. Slower (measured ~56s vs ~23s on a typical machine) but
    /// covers locations the default list does not know about — a new app
    /// vendoring its own Python under a dot-folder the list has never heard
    /// of, for instance. Suitable for a periodic full audit.
    #[arg(long)]
    exhaustive: bool,

    /// Walker threads. 0 selects one per CPU core.
    #[arg(long, default_value_t = 0)]
    threads: usize,
}

/// Roots outside `$HOME` that are scanned in both modes.
///
/// A note on macOS "firmlinks", because it is easy to get wrong: the boot disk
/// is split into a sealed read-only System volume and a writable Data volume,
/// and paths like `/usr/local`, `/opt`, `/Library` and `/Users` are grafted
/// from the Data volume into the System volume's namespace. `statfs` reports
/// *different* filesystem IDs either side of such a graft, which suggests
/// `same_file_system(true)` would stop the walk at `/usr/local` and hide Intel
/// Homebrew. It does not: the walker compares `st_dev` from `lstat`, and
/// firmlinked paths share the same `st_dev` (verified: `/usr` and `/usr/local`
/// both report 16777233). So `/usr` already covers `/usr/local`, and listing it
/// separately would only walk it twice.
///
/// `same_file_system(true)` still earns its keep — it stops the scan from
/// wandering onto genuinely separate mounts such as external drives, disk
/// images and network shares, which do have a distinct `st_dev`.
fn system_roots() -> Vec<PathBuf> {
    ["/Library", "/opt", "/usr", "/Applications"]
        .into_iter()
        .map(PathBuf::from)
        .collect()
}

/// Targeted `$HOME` subdirectories scanned by default, in place of walking
/// all of `$HOME`.
///
/// This is an explicit allowlist, not a denylist of noisy caches — an earlier
/// version of this tool pruned known-noisy trees (`node_modules`, `.git`,
/// package-manager caches) instead. Measurement showed that approach was
/// solving the wrong problem: of the 72 Python-named paths found anywhere
/// under `$HOME` on a real machine, 68 were symlinks, and 63 of those
/// resolved to a *single* binary already reachable via `/opt`. The entire
/// `$HOME` walk — millions of entries — was earning exactly one unique
/// finding that these targeted roots also catch directly, in a fraction of
/// the time.
///
/// `~/Library` is listed as a whole rather than as
/// `~/Library/Application Support` and `~/Library/Python` separately: it
/// already contains both, and listing a directory alongside its own
/// descendant would walk the descendant twice — the same mistake `/usr` and
/// `/usr/local` taught earlier in this file.
///
/// Paths that do not exist on this machine (`~/.pyenv`, `~/miniconda3`, …)
/// are listed anyway and simply skipped by the caller. That costs nothing and
/// means installing a new version manager tomorrow is covered with no code
/// change.
///
/// The known gap: a location this list has never heard of — a new app
/// vendoring its own Python under a novel dot-folder, the way LM Studio once
/// did under `~/.lmstudio` — will not be found here. `--exhaustive` exists as
/// the periodic check against that gap.
fn home_subroots(home: &Path) -> Vec<PathBuf> {
    [
        "Library",
        ".cache/uv",
        ".local/share/uv",
        ".local/bin",
        "Applications",
        ".Trash",
        ".pyenv",
        ".asdf",
        ".rye",
        ".conda",
        ".lmstudio",
        "miniconda3",
        "anaconda3",
        "miniforge3",
        "mambaforge",
    ]
    .into_iter()
    .map(|p| home.join(p))
    .collect()
}

/// The roots scanned when `--root` is not given.
///
/// `exhaustive` selects between the two modes: the targeted `$HOME`
/// subdirectories from `home_subroots`, or bare `$HOME` in full. The two are
/// alternatives, never combined — adding both would walk the subroots a
/// second time as part of the full `$HOME` walk.
fn default_roots(exhaustive: bool) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(home) = std::env::var_os("HOME") {
        let home = PathBuf::from(home);
        if exhaustive {
            roots.push(home);
        } else {
            roots.extend(home_subroots(&home));
        }
    }
    roots.extend(system_roots());
    roots
}

// ─────────────────────────────────────────────────────────────────────────────
// Versions
// ─────────────────────────────────────────────────────────────────────────────

/// A parsed `major.minor.patch`. Deriving `PartialOrd`/`Ord` on a tuple-like
/// struct gives lexicographic comparison field by field, which is exactly
/// semantic-version ordering, so `<` on two `Version`s just works.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Version(u32, u32, u32);

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.0, self.1, self.2)
    }
}

/// Find the first `N.N` or `N.N.N` inside arbitrary text.
///
/// Hand-written rather than using the `regex` crate: the grammar is tiny, and
/// avoiding `regex` keeps the dependency tree to three crates.
fn parse_version(text: &str) -> Option<Version> {
    let bytes = text.as_bytes();
    let mut i = 0;

    while i < bytes.len() {
        if !bytes[i].is_ascii_digit() {
            i += 1;
            continue;
        }

        // `take_number` walks a run of digits and reports where it stopped.
        let take_number = |start: usize| -> (u32, usize) {
            let mut end = start;
            let mut value: u32 = 0;
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                // saturating_mul/add avoid a panic on absurdly long digit runs.
                value = value
                    .saturating_mul(10)
                    .saturating_add((bytes[end] - b'0') as u32);
                end += 1;
            }
            (value, end)
        };

        let (major, after_major) = take_number(i);

        // A bare integer is not a version; we need at least `major.minor`.
        // This is a "let chain" (Rust 2024): several `let` patterns and boolean
        // tests joined by `&&` in one `if`, with earlier bindings visible to
        // later conditions.
        if after_major < bytes.len()
            && bytes[after_major] == b'.'
            && let (minor, after_minor) = take_number(after_major + 1)
            && after_minor > after_major + 1
        {
            // The patch component is optional.
            let patch = if after_minor < bytes.len()
                && bytes[after_minor] == b'.'
                && after_minor + 1 < bytes.len()
                && bytes[after_minor + 1].is_ascii_digit()
            {
                take_number(after_minor + 1).0
            } else {
                0
            };
            return Some(Version(major, minor, patch));
        }

        i = after_major.max(i + 1);
    }

    None
}

// ─────────────────────────────────────────────────────────────────────────────
// Name matching
// ─────────────────────────────────────────────────────────────────────────────

/// Does this filename look like a Python interpreter?
///
/// Equivalent to the regex `^python[0-9.]*$` **case-insensitively**. The case
/// folding is not optional: macOS frameworks ship a binary literally named
/// `Python`, and in `/Library/ManagedFrameworks` alone a case-sensitive match
/// finds 4 entries where a case-insensitive one finds 7.
///
/// This runs once per visited directory entry — millions of times — so it is a
/// plain byte comparison with no allocation and no regex engine.
fn is_python_name(name: &OsStr) -> bool {
    let bytes = name.as_bytes();
    // `strip_prefix` on a slice returns the remainder after the prefix, but it
    // is case-sensitive, so compare the first six bytes explicitly.
    let Some((head, tail)) = bytes.split_at_checked(6) else {
        return false;
    };
    head.eq_ignore_ascii_case(b"python") && tail.iter().all(|b| b.is_ascii_digit() || *b == b'.')
}

// ─────────────────────────────────────────────────────────────────────────────
// Origin and remediation
// ─────────────────────────────────────────────────────────────────────────────

/// What can actually be done about a violation.
///
/// The tool deliberately refuses to `unlink` anything owned by another
/// installer. Deleting a file out of a Homebrew keg or an app bundle leaves the
/// owner's manifest inconsistent and breaks the application; the correct fix is
/// the owner's own uninstall command.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Fix {
    /// A plain file we installed ourselves; `--clean` may delete it.
    Removable,
    /// Owned by a package manager. Report the exact command instead.
    Command(String),
    /// Bundled inside a `.app`; the whole application must be uninstalled.
    AppBundle(String),
    /// Requires a human step rather than a command — MDM-managed, protected by
    /// SIP, or already sitting in the Trash. The note says what to do.
    Manual(&'static str),
}

/// Classify a path into a human-readable origin plus its remediation.
///
/// Order matters. Package-manager ownership is checked *before* the `.app`
/// test, because Homebrew's Python keg contains an `IDLE 3.app` — that is a
/// Homebrew artifact, not an application the user installed.
fn classify_origin(path: &Path) -> (String, Fix) {
    let p = path.to_string_lossy();

    // ── Already discarded, but still on disk ────────────────────────────────
    // Dragging an app to the Trash does not delete it, so the old interpreter
    // is still present and still counts. Checked first: a trashed Homebrew keg
    // or a trashed .app is trash before it is anything else, and "uninstall the
    // app" would be the wrong instruction for something already thrown away.
    if p.contains("/.Trash/") {
        return (
            "trash".into(),
            Fix::Manual("already in the Trash — empty the Trash to delete it"),
        );
    }

    // ── Homebrew ────────────────────────────────────────────────────────────
    if let Some(idx) = p.find("/Cellar/")
        && let Some(formula) = p[idx + "/Cellar/".len()..].split('/').next()
    {
        return (
            format!("homebrew:{formula}"),
            Fix::Command(format!("brew uninstall {formula}")),
        );
    }
    if p.starts_with("/opt/homebrew/") || p.starts_with("/usr/local/Cellar/") {
        return (
            "homebrew".into(),
            Fix::Command("brew uninstall <formula>".into()),
        );
    }

    // ── Managed / protected ─────────────────────────────────────────────────
    if p.contains("/Library/ManagedFrameworks/") {
        return (
            "macos-managed".into(),
            Fix::Manual("managed by MDM — escalate to IT, do not delete"),
        );
    }
    if p.starts_with("/usr/bin/") || p.starts_with("/System/") {
        return (
            "macos-system".into(),
            Fix::Manual("part of macOS and protected by SIP — cannot be removed"),
        );
    }
    if p.contains("/Library/Developer/") {
        return (
            "xcode-cli".into(),
            Fix::Manual("ships with the Xcode command line tools — update Xcode instead"),
        );
    }

    // ── Bundled inside an application ───────────────────────────────────────
    if let Some(bundle) = enclosing_app_bundle(path) {
        let name = Path::new(&bundle)
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| bundle.clone());
        return (format!("app:{name}"), Fix::AppBundle(bundle));
    }

    // ── Python version managers ─────────────────────────────────────────────
    if p.contains("/.cache/uv/") {
        return ("uv-cache".into(), Fix::Command("uv cache clean".into()));
    }
    if p.contains("/uv/python/") {
        return (
            "uv-python".into(),
            Fix::Command("uv python uninstall <version>".into()),
        );
    }
    if p.contains("/.pyenv/") {
        let version = segment_after(&p, "/versions/").unwrap_or_else(|| "<version>".into());
        return (
            "pyenv".into(),
            Fix::Command(format!("pyenv uninstall {version}")),
        );
    }
    if p.contains("/.asdf/") {
        let version = segment_after(&p, "/installs/python/").unwrap_or_else(|| "<version>".into());
        return (
            "asdf".into(),
            Fix::Command(format!("asdf uninstall python {version}")),
        );
    }
    if p.contains("/miniconda3/") || p.contains("/anaconda3/") || p.contains("/miniforge3/") {
        return (
            "conda".into(),
            Fix::Command("conda env remove -n <env>".into()),
        );
    }

    // ── Everything else ─────────────────────────────────────────────────────
    if p.contains("/Library/Frameworks/Python.framework/") {
        return ("python.org".into(), Fix::Removable);
    }
    if p.contains("/.venv/") || p.contains("/venv/") {
        return ("virtualenv".into(), Fix::Removable);
    }
    if p.starts_with("/usr/local/") {
        return ("manual".into(), Fix::Removable);
    }

    ("unknown".into(), Fix::Removable)
}

/// Return the outermost `*.app` directory containing `path`, if any.
fn enclosing_app_bundle(path: &Path) -> Option<String> {
    let mut prefix = PathBuf::new();
    for component in path.components() {
        prefix.push(component);
        if prefix
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("app"))
        {
            return Some(prefix.to_string_lossy().into_owned());
        }
    }
    None
}

/// Pull the path segment that follows `marker`, e.g. the `3.11.9` in
/// `~/.pyenv/versions/3.11.9/bin/python`.
fn segment_after(path: &str, marker: &str) -> Option<String> {
    let idx = path.find(marker)?;
    let rest = &path[idx + marker.len()..];
    let segment = rest.split('/').next()?;
    (!segment.is_empty()).then(|| segment.to_string())
}

// ─────────────────────────────────────────────────────────────────────────────
// Findings
// ─────────────────────────────────────────────────────────────────────────────

/// What a candidate path turned out to be.
#[derive(Debug, Clone)]
enum Kind {
    /// An interpreter older than the threshold. `inferred` marks a version
    /// read off the path because the binary refused to run.
    Violation {
        version: Version,
        fix: Fix,
        inferred: bool,
    },
    /// A symlink whose target no longer exists.
    Broken,
    /// Executable bit set, but `exec` reports ENOEXEC — a dylib, not a program.
    Library,
    /// Matched by name but not runnable (man pages, data files, …).
    NonExecutable,
}

#[derive(Debug, Clone)]
struct Finding {
    path: PathBuf,
    origin: String,
    kind: Kind,
}

// ─────────────────────────────────────────────────────────────────────────────
// Version probing
// ─────────────────────────────────────────────────────────────────────────────

/// Is this file a Mach-O *shared library* rather than a program?
///
/// Frameworks ship a binary named `Python` that carries the executable bit but
/// is a dylib. Trying to run it is not a reliable way to find out: Rust's
/// `Command` reacts to an exec-format failure by silently retrying through
/// `/bin/sh`, which then prints `"<path>: cannot execute binary file"` — and
/// that message embeds the path, so a naive version parse happily extracts the
/// `3.10` out of `.../Versions/3.10/Python` and invents a violation.
///
/// Reading the Mach-O header instead is deterministic, locale-independent, and
/// avoids spawning a process at all.
///
/// Universal ("fat") binaries use a different magic and are not detected here;
/// they fall through to the exec path, which is harmless.
fn is_mach_o_dylib(path: &Path) -> bool {
    let Ok(mut file) = fs::File::open(path) else {
        return false;
    };
    // Bytes 0..4 are the magic; bytes 12..16 are the `filetype` field.
    let mut header = [0u8; 16];
    if file.read_exact(&mut header).is_err() {
        return false;
    }
    if header[..4] != MACHO_MAGIC_64_LE {
        return false;
    }
    let filetype = u32::from_le_bytes([header[12], header[13], header[14], header[15]]);
    filetype == MACHO_TYPE_DYLIB
}

/// Recover a version from the path when the binary itself cannot be run.
///
/// macOS kills app-bundled interpreters with SIGKILL when they are launched
/// outside their bundle (library validation), so `--version` yields nothing at
/// all. Inkscape's bundled 3.10 is exactly this case, and it is a genuine
/// violation — dropping it because the process was killed would hide it.
fn infer_version_from_path(path: &Path) -> Option<Version> {
    // `python3.10` → `3.10`. The name already matched `is_python_name`, so
    // everything after the first six characters is digits and dots.
    if let Some(name) = path.file_name().and_then(|n| n.to_str())
        && let Some(suffix) = name.get(6..)
        && let Some(version) = parse_version(suffix)
    {
        return Some(version);
    }

    // Otherwise look for a path segment that is *entirely* a version number,
    // nearest the file first: `.../Versions/3.10/bin/python3`,
    // `.../python@3.11/...`, `.../.pyenv/versions/3.11.9/...`.
    for component in path.components().rev() {
        let segment = component.as_os_str().to_string_lossy();
        // `python@3.11` → `3.11`
        let candidate = segment.rsplit('@').next().unwrap_or(&segment);
        if !candidate.is_empty()
            && candidate.bytes().all(|b| b.is_ascii_digit() || b == b'.')
            && let Some(version) = parse_version(candidate)
        {
            return Some(version);
        }
    }

    None
}

/// Outcome of running `<binary> --version`.
#[derive(Debug, Clone)]
enum Probe {
    Version(Version),
    /// Ran, but exited non-zero, was killed, or printed nothing parseable.
    Unrunnable,
}

/// Caches `--version` results keyed by *canonical* path.
///
/// A typical machine has `python`, `python3` and `python3.14` in several
/// directories all resolving through symlink chains to one real binary, and
/// uv's cache adds dozens more links to the same target. Canonicalising first
/// means we spawn one process per distinct interpreter instead of one per path.
#[derive(Default)]
struct ProbeCache {
    inner: Mutex<HashMap<PathBuf, Probe>>,
}

impl ProbeCache {
    fn probe(&self, path: &Path) -> Probe {
        // Fall back to the literal path if canonicalisation fails.
        let key = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());

        // Scope the lock so it is released before we spawn a process — holding
        // a mutex across a subprocess call would serialise every worker.
        if let Some(hit) = self.inner.lock().unwrap().get(&key) {
            return hit.clone();
        }

        let result = run_version(&key);
        self.inner.lock().unwrap().insert(key, result.clone());
        result
    }
}

fn run_version(path: &Path) -> Probe {
    let Ok(output) = Command::new(path).arg("--version").output() else {
        return Probe::Unrunnable;
    };

    // Only trust output from a clean exit. Without this guard, the `/bin/sh`
    // fallback described on `is_mach_o_dylib` (exit 126) or any error message
    // that happens to contain a path like `.../3.10/...` would be mistaken for
    // a real version string.
    if !output.status.success() {
        return Probe::Unrunnable;
    }

    // Python 3 prints to stdout; Python 2 prints to stderr.
    let stdout = String::from_utf8_lossy(&output.stdout);
    if let Some(version) = parse_version(&stdout) {
        return Probe::Version(version);
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    parse_version(&stderr).map_or(Probe::Unrunnable, Probe::Version)
}

// ─────────────────────────────────────────────────────────────────────────────
// Classification
// ─────────────────────────────────────────────────────────────────────────────

/// Decide what a candidate path is. Returns `None` when the interpreter is
/// compliant and therefore not worth reporting.
fn classify(path: &Path, threshold: Version, cache: &ProbeCache) -> Option<Finding> {
    let (origin, fix) = classify_origin(path);
    let finding = |kind| {
        Some(Finding {
            path: path.to_path_buf(),
            origin: origin.clone(),
            kind,
        })
    };

    // `symlink_metadata` describes the link itself; `metadata` follows it. A
    // symlink whose target is missing therefore succeeds on the first and fails
    // on the second.
    let link_meta = fs::symlink_metadata(path).ok()?;
    if link_meta.file_type().is_symlink() && fs::metadata(path).is_err() {
        return finding(Kind::Broken);
    }

    let target_meta = fs::metadata(path).ok()?;
    if target_meta.permissions().mode() & 0o111 == 0 {
        return finding(Kind::NonExecutable);
    }

    // Check the Mach-O header before trying to execute: a dylib is not an
    // interpreter, and attempting to run one produces misleading output.
    if is_mach_o_dylib(path) {
        return finding(Kind::Library);
    }

    // Never execute an interpreter that lives inside a .app bundle.
    //
    // macOS library validation kills it immediately with
    // "SIGKILL (Code Signature Invalid)" because it is being launched outside
    // the bundle it was signed for. That is not a silent failure: every attempt
    // pops a "Python quit unexpectedly" dialog and writes a crash report to
    // ~/Library/Logs/DiagnosticReports.
    //
    // Running it gains nothing anyway. Framework layouts encode the version in
    // the path (.../Versions/3.10/bin/python3), and an app-bundled violation is
    // never removed automatically — the remediation is to uninstall the app.
    //
    // The test is structural — "is this inside a .app?" — rather than a check
    // on `fix`. An app sitting in the Trash reports `Fix::Command("empty the
    // Trash")`, but its binaries are still signed and would still be killed.
    let (version, inferred) = if enclosing_app_bundle(path).is_some() {
        match infer_version_from_path(path) {
            Some(version) => (version, true),
            // No version anywhere in the path and we refuse to run it, so there
            // is nothing to compare against the threshold.
            None => return finding(Kind::NonExecutable),
        }
    } else {
        match cache.probe(path) {
            Probe::Version(version) => (version, false),
            // Could not run it. Fall back to the path, so an interpreter macOS
            // refuses to launch is still reported rather than quietly dropped.
            Probe::Unrunnable => match infer_version_from_path(path) {
                Some(version) => (version, true),
                None => return finding(Kind::NonExecutable),
            },
        }
    };

    if version < threshold {
        finding(Kind::Violation {
            version,
            fix,
            inferred,
        })
    } else {
        // Compliant.
        None
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanning
// ─────────────────────────────────────────────────────────────────────────────

/// How long one root took to traverse, and what the walk turned up.
///
/// This is the perf metric: wall-clock time is dominated by the directory
/// walk (syscalls), not by classification (a handful of subprocess spawns), so
/// timing each root separately shows exactly where the ~97% goes — which
/// matters here because `$HOME` alone is typically 90%+ of every entry on the
/// disk.
struct RootTiming {
    root: PathBuf,
    elapsed: Duration,
    /// Every directory entry the walker visited under this root, not just the
    /// ones matching a Python-like name. This is the true traversal volume.
    entries: usize,
    candidates: usize,
    denied: usize,
}

struct ScanOutcome {
    findings: Vec<Finding>,
    timings: Vec<RootTiming>,
}

/// Walk a single root to completion and time it.
///
/// Each root gets its own `build_parallel()` call, so the walk inside a root
/// is still fully parallel across `cli.threads` workers — only the roots
/// themselves are visited one after another rather than interleaved in one
/// shared pool. That is the deliberate trade for this function's reason to
/// exist: a wall-clock number *per root* is only meaningful if one root's
/// threads are not also busy helping a different root at the same moment.
/// Since `$HOME` is the overwhelming majority of the work on a typical
/// machine, the small roots finishing a few hundred milliseconds later than
/// they might have in a combined walk is a cost worth paying for an accurate
/// breakdown.
fn scan_root(
    cli: &Cli,
    root: &Path,
    threshold: Version,
    cache: &Arc<ProbeCache>,
    excludes: &Arc<Vec<String>>,
    live_candidates: &Arc<AtomicUsize>,
) -> (Vec<Finding>, RootTiming) {
    let entries = Arc::new(AtomicUsize::new(0));
    let candidates = Arc::new(AtomicUsize::new(0));
    let denied = Arc::new(AtomicUsize::new(0));

    let mut builder = WalkBuilder::new(root);
    builder
        // Match `fd --unrestricted`: look at hidden files and pay no attention
        // to .gitignore / .ignore files anywhere.
        .hidden(false)
        .ignore(false)
        .git_ignore(false)
        .git_global(false)
        .git_exclude(false)
        .parents(false)
        // Never follow symlinked directories: it invites infinite loops and we
        // reach the real locations through the roots anyway.
        .follow_links(false)
        // Stay on this root's own volume, so the scan never stalls on a
        // network share or an external disk mounted under /Volumes.
        .same_file_system(true)
        .threads(cli.threads);

    if !excludes.is_empty() {
        let excludes = Arc::clone(excludes);
        // Returning false prunes the entry — and, for a directory, everything
        // beneath it.
        builder.filter_entry(move |entry| {
            let path = entry.path().to_string_lossy();
            !excludes.iter().any(|needle| path.contains(needle.as_str()))
        });
    }

    let (tx, rx) = mpsc::channel::<Finding>();
    let start = Instant::now();

    // `build_parallel().run(..)` calls our factory once per worker thread; each
    // call must hand back the closure that thread will use. Cloning the sender
    // per thread is what makes this multi-producer.
    builder.build_parallel().run(|| {
        let tx = tx.clone();
        let cache = Arc::clone(cache);
        let entries = Arc::clone(&entries);
        let candidates = Arc::clone(&candidates);
        let denied = Arc::clone(&denied);
        let live_candidates = Arc::clone(live_candidates);

        Box::new(move |entry| {
            let Ok(entry) = entry else {
                // Unreadable directories are counted, never silently dropped —
                // a partial scan must not be able to report "compliant".
                denied.fetch_add(1, Ordering::Relaxed);
                return WalkState::Continue;
            };
            entries.fetch_add(1, Ordering::Relaxed);

            // `file_type` comes from the directory read itself on macOS, so
            // this costs no extra syscall. Directories are not candidates.
            let is_file_or_link = entry
                .file_type()
                .is_some_and(|t| t.is_file() || t.is_symlink());

            if is_file_or_link && is_python_name(entry.file_name()) {
                candidates.fetch_add(1, Ordering::Relaxed);
                // Fed to the spinner so it keeps moving across root
                // boundaries, not just within one root's walk.
                live_candidates.fetch_add(1, Ordering::Relaxed);
                if let Some(finding) = classify(entry.path(), threshold, &cache) {
                    // Fails only if the receiver is gone, which cannot happen
                    // before `run` returns.
                    let _ = tx.send(finding);
                }
            }

            WalkState::Continue
        })
    });

    // Every worker's clone is dropped when `run` returns; dropping ours closes
    // the channel so the drain below terminates.
    drop(tx);
    let elapsed = start.elapsed();

    let timing = RootTiming {
        root: root.to_path_buf(),
        elapsed,
        entries: entries.load(Ordering::Relaxed),
        candidates: candidates.load(Ordering::Relaxed),
        denied: denied.load(Ordering::Relaxed),
    };

    (rx.iter().collect(), timing)
}

fn scan(
    cli: &Cli,
    roots: &[PathBuf],
    threshold: Version,
    current_root: &Arc<Mutex<PathBuf>>,
    live_candidates: &Arc<AtomicUsize>,
) -> ScanOutcome {
    let cache = Arc::new(ProbeCache::default());
    let excludes = Arc::new(cli.exclude.clone());

    let mut findings = Vec::new();
    let mut timings = Vec::with_capacity(roots.len());

    for root in roots {
        *current_root.lock().unwrap() = root.clone();
        let (root_findings, timing) =
            scan_root(cli, root, threshold, &cache, &excludes, live_candidates);
        findings.extend(root_findings);
        timings.push(timing);
    }

    ScanOutcome { findings, timings }
}

// ─────────────────────────────────────────────────────────────────────────────
// Terminal output
// ─────────────────────────────────────────────────────────────────────────────

/// ANSI escapes, blanked when stdout is not a terminal so that piping or
/// redirecting the report yields clean text.
struct Style {
    reset: &'static str,
    bold: &'static str,
    dim: &'static str,
    red: &'static str,
    yellow: &'static str,
    green: &'static str,
    cyan: &'static str,
}

impl Style {
    fn new(colored: bool) -> Self {
        if colored {
            Self {
                reset: "\x1b[0m",
                bold: "\x1b[1m",
                dim: "\x1b[2m",
                red: "\x1b[31m",
                yellow: "\x1b[33m",
                green: "\x1b[32m",
                cyan: "\x1b[36m",
            }
        } else {
            Self {
                reset: "",
                bold: "",
                dim: "",
                red: "",
                yellow: "",
                green: "",
                cyan: "",
            }
        }
    }
}

const PATH_COL: usize = 120;
const VERSION_COL: usize = 10;

/// Pad or truncate to a fixed width so columns line up.
fn col(text: &str, width: usize) -> String {
    let count = text.chars().count();
    if count >= width {
        let mut out: String = text.chars().take(width.saturating_sub(1)).collect();
        out.push(' ');
        out
    } else {
        format!("{text:<width$}")
    }
}

/// A spinner on stderr, so a scan that takes the better part of a minute does
/// not look like a hang. Runs only when stderr is a terminal.
struct Spinner {
    done: Arc<AtomicBool>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl Spinner {
    fn start(candidates: Arc<AtomicUsize>, current_root: Arc<Mutex<PathBuf>>) -> Self {
        let done = Arc::new(AtomicBool::new(false));
        let handle = if io::stderr().is_terminal() {
            let done = Arc::clone(&done);
            Some(std::thread::spawn(move || {
                let frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
                let mut i = 0;
                while !done.load(Ordering::Relaxed) {
                    let root = current_root.lock().unwrap().display().to_string();
                    eprint!(
                        "\r\x1b[2m{} scanning {}…  candidates: {}\x1b[0m\x1b[K",
                        frames[i % frames.len()],
                        root,
                        candidates.load(Ordering::Relaxed)
                    );
                    let _ = io::stderr().flush();
                    i += 1;
                    std::thread::sleep(Duration::from_millis(80));
                }
                // Clear the line on the way out.
                eprint!("\r\x1b[2K");
                let _ = io::stderr().flush();
            }))
        } else {
            None
        };
        Self { done, handle }
    }

    fn stop(mut self) {
        self.done.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report
// ─────────────────────────────────────────────────────────────────────────────

/// Split findings into the buckets the report and the cleaner both need.
struct Buckets<'a> {
    violations: Vec<&'a Finding>,
    broken: Vec<&'a Finding>,
    libraries: Vec<&'a Finding>,
    non_exec: Vec<&'a Finding>,
}

fn bucket(findings: &[Finding]) -> Buckets<'_> {
    let mut b = Buckets {
        violations: Vec::new(),
        broken: Vec::new(),
        libraries: Vec::new(),
        non_exec: Vec::new(),
    };
    for f in findings {
        match f.kind {
            Kind::Violation { .. } => b.violations.push(f),
            Kind::Broken => b.broken.push(f),
            Kind::Library => b.libraries.push(f),
            Kind::NonExecutable => b.non_exec.push(f),
        }
    }
    // Oldest first, then by path so the report is stable between runs.
    b.violations.sort_by_key(|f| {
        let version = match &f.kind {
            Kind::Violation { version, .. } => *version,
            _ => Version(0, 0, 0),
        };
        (version, f.path.clone())
    });
    b
}

fn write_report(out: &mut impl Write, s: &Style, b: &Buckets<'_>, verbose: bool) -> io::Result<()> {
    if !b.violations.is_empty() {
        writeln!(
            out,
            "\n{}{}VIOLATIONS ({}) — NOT COMPLIANT{}",
            s.bold,
            s.red,
            b.violations.len(),
            s.reset
        )?;
        writeln!(
            out,
            "{}{}{}ORIGIN{}",
            s.bold,
            col("VERSION", VERSION_COL),
            col("PATH", PATH_COL),
            s.reset
        )?;
        for f in &b.violations {
            let Kind::Violation {
                version,
                fix,
                inferred,
            } = &f.kind
            else {
                continue;
            };
            // A trailing `*` marks a version taken from the path because the
            // binary could not be executed.
            let shown = if *inferred {
                format!("{version}*")
            } else {
                version.to_string()
            };
            writeln!(
                out,
                "{}{}{}{}{}{}{}",
                s.red,
                col(&shown, VERSION_COL),
                s.reset,
                col(&f.path.to_string_lossy(), PATH_COL),
                s.dim,
                f.origin,
                s.reset
            )?;
            // Anything we will not delete ourselves gets an explicit
            // remediation line, so the report is always actionable.
            match fix {
                Fix::Removable => {}
                Fix::Command(cmd) => writeln!(
                    out,
                    "{}{:>width$}↳ remove with: {}{}{}",
                    s.dim,
                    "",
                    s.cyan,
                    cmd,
                    s.reset,
                    width = VERSION_COL
                )?,
                Fix::AppBundle(bundle) => writeln!(
                    out,
                    "{}{:>width$}↳ bundled in {}{}{}{} — uninstall the app; deleting this file breaks it{}",
                    s.dim,
                    "",
                    s.reset,
                    s.cyan,
                    bundle,
                    s.dim,
                    s.reset,
                    width = VERSION_COL
                )?,
                Fix::Manual(note) => writeln!(
                    out,
                    "{}{:>width$}↳ {}{}",
                    s.dim,
                    "",
                    note,
                    s.reset,
                    width = VERSION_COL
                )?,
            }
        }

        // Explain the `*` marker only when at least one row carries it.
        if b.violations
            .iter()
            .any(|f| matches!(f.kind, Kind::Violation { inferred: true, .. }))
        {
            writeln!(
                out,
                "{}  * version read from the path — the binary was not run{}",
                s.dim, s.reset
            )?;
        }
    }

    if !b.broken.is_empty() {
        writeln!(
            out,
            "\n{}{}BROKEN SYMLINKS ({}){}",
            s.bold,
            s.yellow,
            b.broken.len(),
            s.reset
        )?;
        writeln!(out, "{}{}ORIGIN{}", s.bold, col("PATH", PATH_COL), s.reset)?;
        for f in &b.broken {
            writeln!(
                out,
                "{}{}{}{}{}{}",
                s.yellow,
                col(&f.path.to_string_lossy(), PATH_COL),
                s.reset,
                s.dim,
                f.origin,
                s.reset
            )?;
        }
    }

    if verbose {
        for (title, group) in [
            ("SHARED LIBRARIES", &b.libraries),
            ("NON-EXECUTABLE MATCHES", &b.non_exec),
        ] {
            if group.is_empty() {
                continue;
            }
            writeln!(
                out,
                "\n{}{}{} ({}) — informational{}",
                s.bold,
                s.dim,
                title,
                group.len(),
                s.reset
            )?;
            for f in group.iter() {
                writeln!(
                    out,
                    "{}{}{}{}",
                    s.dim,
                    col(&f.path.to_string_lossy(), PATH_COL),
                    f.origin,
                    s.reset
                )?;
            }
        }
    }

    Ok(())
}

/// Column widths for the timing table. Roots are short paths, so this needs
/// far less room than `PATH_COL`.
const ROOT_COL: usize = 40;
const NUMBER_COL: usize = 12;

/// A perf metric: how long the walk spent under each root, and how much of
/// the disk that root actually represents.
///
/// The walk is ~97% of this tool's runtime, so this table is the answer to
/// "where did the time go" — on most machines `$HOME` alone will dwarf every
/// other root, which is exactly the kind of thing worth being able to see
/// rather than assume.
fn write_timing_report(out: &mut impl Write, s: &Style, timings: &[RootTiming]) -> io::Result<()> {
    // Slowest first, so the root worth investigating leads.
    let mut sorted: Vec<&RootTiming> = timings.iter().collect();
    sorted.sort_by_key(|t| std::cmp::Reverse(t.elapsed));

    let total_elapsed: Duration = timings.iter().map(|t| t.elapsed).sum();
    let total_entries: usize = timings.iter().map(|t| t.entries).sum();

    writeln!(out, "\n{}TIMING{}", s.bold, s.reset)?;
    writeln!(
        out,
        "{}{}{}{}{}{}",
        s.bold,
        col("ROOT", ROOT_COL),
        col("TIME", NUMBER_COL),
        col("ENTRIES", NUMBER_COL),
        col("CANDIDATES", NUMBER_COL),
        s.reset
    )?;

    for t in &sorted {
        let share = if total_entries > 0 {
            t.entries as f64 * 100.0 / total_entries as f64
        } else {
            0.0
        };
        writeln!(
            out,
            "{}{}{}{}{}  {}({:>4.1}% of entries){}",
            col(&t.root.to_string_lossy(), ROOT_COL),
            col(&format_duration(t.elapsed), NUMBER_COL),
            col(&t.entries.to_string(), NUMBER_COL),
            col(&t.candidates.to_string(), NUMBER_COL),
            s.dim,
            s.dim,
            share,
            s.reset
        )?;
        if t.denied > 0 {
            writeln!(
                out,
                "{}{}↳ {} path(s) denied while walking this root{}",
                s.dim,
                " ".repeat(ROOT_COL),
                t.denied,
                s.reset
            )?;
        }
    }

    writeln!(
        out,
        "{}{}{}{}{}",
        s.bold,
        col("total (sum of roots)", ROOT_COL),
        col(&format_duration(total_elapsed), NUMBER_COL),
        col(&total_entries.to_string(), NUMBER_COL),
        s.reset
    )?;
    writeln!(
        out,
        "{}note: roots are walked one after another, so this total is the scan's wall-clock time{}",
        s.dim, s.reset
    )?;

    Ok(())
}

/// `1.234s` style formatting — plain seconds with millisecond precision reads
/// better here than `Debug`'s `1.234567891s`.
fn format_duration(d: Duration) -> String {
    format!("{:.3}s", d.as_secs_f64())
}

// ─────────────────────────────────────────────────────────────────────────────
// Cleanup
// ─────────────────────────────────────────────────────────────────────────────

fn confirm(prompt: &str, assume_yes: bool) -> bool {
    if assume_yes {
        return true;
    }
    print!("{prompt} [y/N] ");
    let _ = io::stdout().flush();
    let mut answer = String::new();
    if io::stdin().read_line(&mut answer).is_err() {
        return false;
    }
    answer.trim().eq_ignore_ascii_case("y")
}

struct CleanReport {
    removed: usize,
    skipped: usize,
    manual: usize,
}

/// Delete what is safe to delete.
///
/// Only `Fix::Removable` violations and broken symlinks are touched. Everything
/// else was already reported with instructions and is merely counted here, so
/// the exit status still reflects that the machine is not compliant.
fn clean(
    out: &mut impl Write,
    s: &Style,
    b: &Buckets<'_>,
    assume_yes: bool,
) -> io::Result<CleanReport> {
    let removable: Vec<&Finding> = b
        .violations
        .iter()
        .copied()
        .filter(|f| matches!(&f.kind, Kind::Violation { fix, .. } if *fix == Fix::Removable))
        .chain(b.broken.iter().copied())
        .collect();

    let manual = b.violations.len()
        - b.violations
            .iter()
            .filter(|f| matches!(&f.kind, Kind::Violation { fix, .. } if *fix == Fix::Removable))
            .count();

    let mut report = CleanReport {
        removed: 0,
        skipped: 0,
        manual,
    };

    if removable.is_empty() {
        return Ok(report);
    }

    writeln!(out, "\n{}CLEANUP{}", s.bold, s.reset)?;
    out.flush()?;

    for f in removable {
        let label = match &f.kind {
            Kind::Violation { version, .. } => format!("{}[violation {version}]{}", s.red, s.reset),
            _ => format!("{}[broken symlink]{}", s.yellow, s.reset),
        };
        let prompt = format!("Remove {label} {}{}{}?", s.cyan, f.path.display(), s.reset);

        if !confirm(&prompt, assume_yes) {
            writeln!(out, "  {}Skipped.{}", s.dim, s.reset)?;
            report.skipped += 1;
            continue;
        }

        // `remove_file` deletes the symlink itself, never the target, and never
        // touches the parent directory.
        match fs::remove_file(&f.path) {
            Ok(()) => {
                writeln!(out, "  {}Removed.{}", s.green, s.reset)?;
                report.removed += 1;
            }
            Err(err) => {
                writeln!(out, "  {}Failed: {err}{}", s.red, s.reset)?;
                report.skipped += 1;
            }
        }
        out.flush()?;
    }

    Ok(report)
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

/// `main` returns `ExitCode` so the exit status is part of the normal return
/// path rather than a `process::exit` call that would skip destructors.
fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(err) => {
            eprintln!("error: {err:#}");
            ExitCode::from(2)
        }
    }
}

fn run() -> anyhow::Result<ExitCode> {
    let cli = Cli::parse();

    let threshold = parse_version(&cli.below)
        .ok_or_else(|| anyhow::anyhow!("invalid version threshold: {}", cli.below))?;

    // Keep only roots that exist, so a machine without /opt is not an error.
    let requested = if cli.root.is_empty() {
        default_roots(cli.exhaustive)
    } else {
        cli.root.clone()
    };
    let roots: Vec<PathBuf> = requested.into_iter().filter(|p| p.exists()).collect();
    anyhow::ensure!(!roots.is_empty(), "no scan roots exist");

    let colored = io::stdout().is_terminal();
    let s = Style::new(colored);

    eprintln!(
        "{}Scanning for Python installations below {}…{}",
        s.bold, cli.below, s.reset
    );
    for root in &roots {
        eprintln!("{}  root: {}{}", s.dim, root.display(), s.reset);
    }

    let live_candidates = Arc::new(AtomicUsize::new(0));
    let current_root = Arc::new(Mutex::new(roots[0].clone()));
    let spinner = Spinner::start(Arc::clone(&live_candidates), Arc::clone(&current_root));
    let outcome = scan(&cli, &roots, threshold, &current_root, &live_candidates);
    spinner.stop();

    let buckets = bucket(&outcome.findings);

    // Buffer the whole report and write it once: locking stdout per line is
    // both slower and prone to interleaving.
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    write_report(&mut out, &s, &buckets, cli.verbose)?;

    let total_candidates: usize = outcome.timings.iter().map(|t| t.candidates).sum();
    let total_denied: usize = outcome.timings.iter().map(|t| t.denied).sum();

    writeln!(
        out,
        "\n{}SUMMARY{}  candidates: {}   violations: {}{}{}   broken: {}{}{}",
        s.bold,
        s.reset,
        total_candidates,
        s.red,
        buckets.violations.len(),
        s.reset,
        s.yellow,
        buckets.broken.len(),
        s.reset
    )?;
    if cli.verbose {
        writeln!(
            out,
            "{}         libraries: {}   non-executable: {}{}",
            s.dim,
            buckets.libraries.len(),
            buckets.non_exec.len(),
            s.reset
        )?;
    }
    if total_denied > 0 {
        writeln!(
            out,
            "{}         {} path(s) were unreadable and could not be checked{}",
            s.yellow, total_denied, s.reset
        )?;
    }

    write_timing_report(&mut out, &s, &outcome.timings)?;

    let mut cleaned = None;
    if cli.clean {
        out.flush()?;
        cleaned = Some(clean(&mut out, &s, &buckets, cli.yes)?);
    }

    if let Some(report) = &cleaned {
        writeln!(
            out,
            "\n{}CLEANUP SUMMARY{}  removed: {}{}{}   skipped: {}{}{}   manual action required: {}{}{}",
            s.bold,
            s.reset,
            s.green,
            report.removed,
            s.reset,
            s.dim,
            report.skipped,
            s.reset,
            s.yellow,
            report.manual,
            s.reset
        )?;
    }

    // Compliance is decided by violations only; broken symlinks never affect
    // it. Re-stat each one so anything just deleted stops counting.
    let remaining = buckets
        .violations
        .iter()
        .filter(|f| fs::symlink_metadata(&f.path).is_ok())
        .count();

    let code = if remaining == 0 {
        writeln!(
            out,
            "\n{}{}COMPLIANT — no Python installations below {} found.{}",
            s.green, s.bold, cli.below, s.reset
        )?;
        ExitCode::SUCCESS
    } else {
        writeln!(
            out,
            "\n{}{}NOT COMPLIANT — {} violation(s) remain.{}",
            s.red, s.bold, remaining, s.reset
        )?;
        if !cli.clean {
            writeln!(
                out,
                "{}run with --clean to remove the ones that can be removed automatically{}",
                s.dim, s.reset
            )?;
        }
        ExitCode::from(1)
    };

    out.flush()?;
    Ok(code)
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_home_subroots_target_known_install_locations_only() {
        let home = Path::new("/Users/x");
        let subroots = home_subroots(home);

        for expect in [
            "/Users/x/Library",
            "/Users/x/.cache/uv",
            "/Users/x/.local/share/uv",
            "/Users/x/.Trash",
        ] {
            assert!(
                subroots.contains(&PathBuf::from(expect)),
                "missing {expect}"
            );
        }

        // Bare $HOME must never appear in the targeted list — that would
        // defeat the entire point of scoping the walk.
        assert!(!subroots.contains(&home.to_path_buf()));
    }

    #[test]
    fn exhaustive_mode_replaces_subroots_with_bare_home() {
        // SAFETY: tests run single-threaded within this process is not
        // guaranteed, but HOME is only read here, never written, so a
        // concurrent reader sees a consistent value either way.
        let home = std::env::var_os("HOME").expect("HOME must be set to run this test");
        let home = PathBuf::from(home);

        let exhaustive = default_roots(true);
        assert!(exhaustive.contains(&home));
        for subroot in home_subroots(&home) {
            assert!(
                !exhaustive.contains(&subroot),
                "{} should not appear alongside bare $HOME — it would be walked twice",
                subroot.display()
            );
        }

        let targeted = default_roots(false);
        assert!(!targeted.contains(&home));
    }

    #[test]
    fn no_default_root_is_a_prefix_of_another() {
        // A repeat of the /usr + /usr/local mistake, in either mode, would
        // silently double the work for that subtree.
        for exhaustive in [false, true] {
            let roots = default_roots(exhaustive);
            for a in &roots {
                for b in &roots {
                    if a == b {
                        continue;
                    }
                    assert!(
                        !b.starts_with(a),
                        "{} (exhaustive={exhaustive}) contains {}, so it would be walked twice",
                        a.display(),
                        b.display()
                    );
                }
            }
        }
    }

    #[test]
    fn parses_versions_from_noise() {
        assert_eq!(parse_version("Python 3.13.5"), Some(Version(3, 13, 5)));
        assert_eq!(parse_version("Python 3.10"), Some(Version(3, 10, 0)));
        assert_eq!(parse_version("3.14.7"), Some(Version(3, 14, 7)));
        assert_eq!(parse_version("Python 2.7.18"), Some(Version(2, 7, 18)));
        assert_eq!(parse_version("no digits here"), None);
        assert_eq!(parse_version("42"), None);
    }

    #[test]
    fn version_ordering_is_numeric_not_lexicographic() {
        // The bug a string comparison would introduce: "3.9" > "3.13".
        assert!(Version(3, 9, 0) < Version(3, 13, 0));
        assert!(Version(3, 13, 5) > Version(3, 13, 0));
        assert!(Version(2, 7, 18) < Version(3, 0, 0));
    }

    #[test]
    fn matches_interpreter_names_case_insensitively() {
        let yes = ["python", "Python", "python3", "python3.11", "PYTHON3.14"];
        for name in yes {
            assert!(is_python_name(OsStr::new(name)), "should match {name}");
        }
        let no = [
            "pytho",
            "python3.11.dylib",
            "pythonw",
            "python-config",
            "ipython",
        ];
        for name in no {
            assert!(!is_python_name(OsStr::new(name)), "should not match {name}");
        }
    }

    #[test]
    fn homebrew_wins_over_app_bundle() {
        // Homebrew's Python keg contains an "IDLE 3.app"; that is a Homebrew
        // artifact, so the fix must be `brew uninstall`, not "uninstall an app".
        let path =
            Path::new("/opt/homebrew/Cellar/python@3.14/3.14.7/IDLE 3.app/Contents/MacOS/Python");
        let (origin, fix) = classify_origin(path);
        assert_eq!(origin, "homebrew:python@3.14");
        assert_eq!(fix, Fix::Command("brew uninstall python@3.14".into()));
    }

    #[test]
    fn detects_app_bundled_interpreter() {
        let path = Path::new(
            "/Applications/Inkscape.app/Contents/Frameworks/Python.framework/Versions/3.10/bin/python3.10",
        );
        let (origin, fix) = classify_origin(path);
        assert_eq!(origin, "app:Inkscape.app");
        assert_eq!(fix, Fix::AppBundle("/Applications/Inkscape.app".into()));
    }

    #[test]
    fn mdm_managed_is_never_removable() {
        let path = Path::new(
            "/Library/ManagedFrameworks/Python/Python3.framework/Versions/3.13/bin/python3.13",
        );
        let (origin, fix) = classify_origin(path);
        assert_eq!(origin, "macos-managed");
        assert!(matches!(fix, Fix::Manual(_)));
    }

    #[test]
    fn system_python_is_protected() {
        let (origin, fix) = classify_origin(Path::new("/usr/bin/python3"));
        assert_eq!(origin, "macos-system");
        assert!(matches!(fix, Fix::Manual(_)));
    }

    #[test]
    fn trashed_app_is_reported_as_trash_not_as_an_app_to_uninstall() {
        // Moving an app to the Trash leaves the interpreter on disk, so it must
        // still be counted — but the fix is to empty the Trash, not to
        // "uninstall the app", which the user has already done.
        let (origin, fix) = classify_origin(Path::new(
            "/Users/x/.Trash/Inkscape.app/Contents/Frameworks/Python.framework/Versions/3.10/bin/python3.10",
        ));
        assert_eq!(origin, "trash");
        assert!(matches!(fix, Fix::Manual(_)));
    }

    #[test]
    fn infers_version_from_file_name() {
        assert_eq!(
            infer_version_from_path(Path::new("/x/bin/python3.10")),
            Some(Version(3, 10, 0))
        );
        assert_eq!(
            infer_version_from_path(Path::new("/x/bin/python3.11.9")),
            Some(Version(3, 11, 9))
        );
    }

    #[test]
    fn infers_version_from_path_segment_when_name_has_none() {
        // Inkscape's `bin/python3` carries no version in its name, but the
        // framework directory above it does.
        assert_eq!(
            infer_version_from_path(Path::new(
                "/Applications/Inkscape.app/Contents/Frameworks/Python.framework/Versions/3.10/bin/python3"
            )),
            Some(Version(3, 10, 0))
        );
        // Homebrew's `python@3.11` keg naming.
        assert_eq!(
            infer_version_from_path(Path::new("/opt/homebrew/opt/python@3.11/bin/python3")),
            Some(Version(3, 11, 0))
        );
    }

    #[test]
    fn refuses_to_invent_a_version() {
        // No digits anywhere: must not guess.
        assert_eq!(infer_version_from_path(Path::new("/usr/bin/python")), None);
        // `Contents`, `MacOS` etc. are not version segments.
        assert_eq!(
            infer_version_from_path(Path::new("/Applications/Foo.app/Contents/MacOS/python")),
            None
        );
    }

    #[test]
    fn error_text_containing_a_path_is_not_a_version() {
        // The exact regression: /bin/sh's fallback message embeds the path, and
        // a bare parse would pull "3.10" straight out of it. run_version guards
        // against this by requiring a successful exit, but make sure the shape
        // of the message is understood.
        let sh_error = "/A/Python.framework/Versions/3.10/Python: cannot execute binary file";
        assert_eq!(parse_version(sh_error), Some(Version(3, 10, 0)));
        // …which is precisely why the exit-status check exists in run_version.
    }

    #[test]
    fn extracts_pyenv_version() {
        let (origin, fix) =
            classify_origin(Path::new("/Users/x/.pyenv/versions/3.11.9/bin/python3.11"));
        assert_eq!(origin, "pyenv");
        assert_eq!(fix, Fix::Command("pyenv uninstall 3.11.9".into()));
    }
}
