//! Resolves `filesystem.hidden` into concrete paths. bwrap can only cover a
//! path that exists, so a glob such as `~/repos/**/.env` is expanded by
//! walking its base dir on every start (~0.1s for ~/repos). node_modules and
//! .git are never descended into: walking node_modules alone takes seconds.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{Context, Result};
use globset::{GlobBuilder, GlobMatcher};
use ignore::{WalkBuilder, WalkState};

use crate::config::expand;

const GLOB_CHARS: [char; 4] = ['*', '?', '[', '{'];
const SKIP_DIRS: [&str; 2] = ["node_modules", ".git"];

/// Existing paths for every entry: plain paths as-is, globs expanded.
/// Symlinks are resolved; missing paths are skipped.
pub fn resolve(entries: &[String], home: &Path) -> Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    for entry in entries {
        let path = expand(entry, home);
        if !path.to_string_lossy().contains(GLOB_CHARS) {
            out.extend(path.canonicalize().ok());
            continue;
        }
        let (base, rest) = split_glob(&path);
        let matcher = GlobBuilder::new(&rest)
            .literal_separator(true)
            .build()
            .with_context(|| format!("invalid glob '{entry}'"))?
            .compile_matcher();
        if let Ok(base) = base.canonicalize() {
            out.extend(walk(&base, &matcher));
        }
    }
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

fn walk(base: &Path, matcher: &GlobMatcher) -> Vec<PathBuf> {
    let mut walk = WalkBuilder::new(base);
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
                    .is_ok_and(|rel| matcher.is_match(rel))
            {
                found.lock().unwrap().push(e.into_path());
            }
            WalkState::Continue
        })
    });
    found.into_inner().unwrap()
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
    fn hides_exact_names_only_and_skips_node_modules() {
        let root = std::env::temp_dir().join(format!("pi-safe-hide-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        for d in ["app/pkg", "app/node_modules/dep", "secret-dir"] {
            std::fs::create_dir_all(root.join(d)).unwrap();
        }
        for f in [
            "app/.env",
            "app/pkg/.env",
            "app/.env.example",
            "app/.env.aws.dev",
            "app/node_modules/dep/.env",
        ] {
            std::fs::write(root.join(f), "x").unwrap();
        }
        let home = Path::new("/nonexistent");
        let entries = [
            format!("{}/**/.env", root.display()),
            format!("{}/secret-dir", root.display()),
            format!("{}/missing", root.display()),
        ];
        let found = resolve(&entries, home).unwrap();
        let root = root.canonicalize().unwrap();
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(
            found,
            [
                root.join("app/.env"),
                root.join("app/pkg/.env"),
                root.join("secret-dir")
            ]
        );
    }
}
