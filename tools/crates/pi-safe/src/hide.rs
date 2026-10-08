//! Resolves `filesystem.hidden` into concrete paths. bwrap can only cover a
//! path that exists, so a glob such as `~/repos/**/.env` is expanded by a
//! walk on every start. Only trees the sandbox can see are walked, and globs
//! sharing a base dir share one walk: a dozen secret patterns over ~/repos
//! cost one pass, not twelve.
//!
//! `SKIP_DIRS` are never descended into: walking node_modules alone takes
//! seconds, and the build and cache dirs of every repo in ~/repos (one Cargo
//! `target/` is ~3.5 GB) made each start slow. They hold generated files, not
//! a hand-written `.env`.
//!
//! Glob matches git tracks stay visible: their content is in `.git`, which
//! the sandbox reads anyway, and committed files such as `.env.aws.dev` or
//! `.env.example` are configuration the agent needs. Measured on ~/repos, 229
//! of 234 matches were committed; the 5 left were the actual secrets. What is
//! hidden is what git does not track - gitignored, or not yet ignored.

use std::collections::{BTreeMap, HashSet};
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

use anyhow::{Context, Result};
use globset::{GlobBuilder, GlobSet, GlobSetBuilder};
use ignore::{WalkBuilder, WalkState};

use crate::config::expand;

const GLOB_CHARS: [char; 4] = ['*', '?', '[', '{'];
const SKIP_DIRS: [&str; 14] = [
    ".git",
    // JavaScript
    "node_modules",
    ".pnpm-store",
    ".next",
    ".turbo",
    // Rust, Go and generic build output
    "target",
    "dist",
    "build",
    // Python
    ".venv",
    "__pycache__",
    ".mypy_cache",
    ".ruff_cache",
    // Terraform providers, generic caches
    ".terraform",
    ".cache",
];

/// Existing paths for every entry, limited to `visible` trees (canonical
/// paths): plain paths as-is, globs expanded minus the files git tracks.
/// Symlinks are resolved; missing or invisible paths are skipped.
pub fn resolve(entries: &[String], home: &Path, visible: &[PathBuf]) -> Result<Vec<PathBuf>> {
    let is_visible = |p: &Path| visible.iter().any(|v| p.starts_with(v));
    let mut out = Vec::new();
    let mut by_base: BTreeMap<PathBuf, GlobSetBuilder> = BTreeMap::new();
    for entry in entries {
        let path = expand(entry, home);
        if !path.to_string_lossy().contains(GLOB_CHARS) {
            out.extend(path.canonicalize().ok().filter(|p| is_visible(p)));
            continue;
        }
        let (base, rest) = split_glob(&path);
        let glob = GlobBuilder::new(&rest)
            .literal_separator(true)
            .build()
            .with_context(|| format!("invalid glob '{entry}'"))?;
        let Ok(base) = base.canonicalize() else {
            continue;
        };
        by_base
            .entry(base)
            .or_insert_with(GlobSetBuilder::new)
            .add(glob);
    }
    let mut matches = Vec::new();
    for (base, set) in by_base {
        let set = set.build()?;
        // walk the base if it is visible, else only the visible trees in it
        let roots: Vec<&Path> = if is_visible(&base) {
            vec![&base]
        } else {
            visible
                .iter()
                .filter(|v| v.starts_with(&base))
                .map(PathBuf::as_path)
                .collect()
        };
        for root in roots {
            matches.extend(walk(root, &base, &set));
        }
    }
    out.extend(drop_tracked(matches));
    out.sort();
    out.dedup();
    Ok(out)
}

/// `/a/b/**/.env` -> (`/a/b`, `**/.env`): the literal dirs to walk, and the
/// glob to match paths below them against.
fn split_glob(path: &Path) -> (PathBuf, String) {
    let mut base = PathBuf::new();
    let mut rest: Vec<String> = Vec::new();
    for c in path.components() {
        let s = c.as_os_str().to_string_lossy();
        if rest.is_empty() && !s.contains(GLOB_CHARS) {
            base.push(c);
        } else {
            rest.push(s.into_owned());
        }
    }
    (base, rest.join("/"))
}

/// Paths below `root` whose path relative to `base` matches `set`.
fn walk(root: &Path, base: &Path, set: &GlobSet) -> Vec<PathBuf> {
    let mut walk = WalkBuilder::new(root);
    walk.standard_filters(false)
        .hidden(false)
        .follow_links(false)
        .filter_entry(|e| {
            let is_dir = e.file_type().is_some_and(|t| t.is_dir());
            !(is_dir && e.depth() > 0 && SKIP_DIRS.iter().any(|s| e.file_name() == *s))
        });
    let found = Mutex::new(Vec::new());
    walk.build_parallel().run(|| {
        Box::new(|entry| {
            if let Ok(e) = entry
                && !e.path_is_symlink()
                && e.path()
                    .strip_prefix(base)
                    .is_ok_and(|rel| set.is_match(rel))
            {
                found.lock().unwrap().push(e.into_path());
            }
            WalkState::Continue
        })
    });
    found.into_inner().unwrap()
}

/// `paths` minus the files git tracks, with one `git ls-files` per repo. A
/// path outside any repo, or a repo git cannot read, stays hidden: failing
/// closed costs the agent a file, failing open would leak one.
fn drop_tracked(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut by_repo: BTreeMap<PathBuf, Vec<PathBuf>> = BTreeMap::new();
    let mut out = Vec::new();
    for p in paths {
        // `.git` is a dir in a clone, a file in a worktree
        match p.ancestors().skip(1).find(|d| d.join(".git").exists()) {
            Some(repo) => by_repo.entry(repo.to_path_buf()).or_default().push(p),
            None => out.push(p),
        }
    }
    for (repo, paths) in by_repo {
        let tracked = tracked(&repo, &paths);
        out.extend(paths.into_iter().filter(|p| !tracked.contains(p)));
    }
    out
}

/// Which of `paths` (all inside `repo`) are in its index.
fn tracked(repo: &Path, paths: &[PathBuf]) -> HashSet<PathBuf> {
    let rels = paths.iter().filter_map(|p| p.strip_prefix(repo).ok());
    // literal: a file name such as `[id].env` is not a pathspec glob
    let out = Command::new("git")
        .arg("--literal-pathspecs")
        .arg("-C")
        .arg(repo)
        .args(["ls-files", "-z", "--"])
        .args(rels)
        .output();
    match out {
        Ok(o) if o.status.success() => o
            .stdout
            .split(|b| *b == 0)
            .filter(|s| !s.is_empty())
            .map(|s| repo.join(OsStr::from_bytes(s)))
            .collect(),
        _ => HashSet::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_literal_base_from_glob() {
        let (base, rest) = split_glob(Path::new("/h/repos/**/.env"));
        assert_eq!(
            (base, rest.as_str()),
            (PathBuf::from("/h/repos"), "**/.env")
        );
        let (base, rest) = split_glob(Path::new("/h/repos/*/x/*.pem"));
        assert_eq!(
            (base, rest.as_str()),
            (PathBuf::from("/h/repos"), "*/x/*.pem")
        );
    }

    #[test]
    fn hides_untracked_matches_but_not_tracked_ones_or_build_dirs() {
        let root = std::env::temp_dir().join(format!("pi-safe-hide-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        for d in [
            "app/pkg",
            "app/node_modules/dep",
            "app/target/x",
            "loose",
            "secret-dir",
        ] {
            std::fs::create_dir_all(root.join(d)).unwrap();
        }
        for f in [
            "app/.env",
            "app/pkg/.env",
            "app/.env.local",
            "app/.env.aws.dev",
            "app/.env.example",
            "app/tls.pem",
            "app/README.md",
            "app/node_modules/dep/.env",
            "app/target/x/.env",
            "loose/.env.example",
        ] {
            std::fs::write(root.join(f), "x").unwrap();
        }
        // a repo whose committed config must stay readable; `loose` is no repo
        let git = |args: &[&str]| {
            let ok = Command::new("git")
                .arg("-C")
                .arg(root.join("app"))
                .args(args)
                .status()
                .unwrap()
                .success();
            assert!(ok, "git {args:?}");
        };
        git(&["init", "-q"]);
        git(&["add", ".env.aws.dev", ".env.example"]);

        let home = Path::new("/nonexistent");
        let entries = [
            format!("{}/**/.env", root.display()),
            format!("{}/**/.env.*", root.display()),
            format!("{}/**/*.pem", root.display()),
            format!("{}/secret-dir", root.display()),
            format!("{}/missing", root.display()),
        ];
        let root = root.canonicalize().unwrap();
        let everything = resolve(&entries, home, std::slice::from_ref(&root)).unwrap();
        // only app/pkg visible (like a project): nothing outside it is walked
        let pkg_only = resolve(&entries, home, &[root.join("app/pkg")]).unwrap();
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(
            everything,
            [
                root.join("app/.env"),
                root.join("app/.env.local"),
                root.join("app/pkg/.env"),
                root.join("app/tls.pem"),
                root.join("loose/.env.example"),
                root.join("secret-dir")
            ]
        );
        assert_eq!(pkg_only, [root.join("app/pkg/.env")]);
    }
}
