//! Resolves `filesystem.hidden` into concrete paths. bwrap can only cover a
//! path that exists, so a glob such as `~/repos/**/.env` is expanded by a
//! walk on every start. Only trees the sandbox can see are walked: without
//! `--context` that is just the project, not all of ~/repos (~0.1s).
//! node_modules and .git are never descended into: walking node_modules alone
//! takes seconds.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{Context, Result};
use globset::{GlobBuilder, GlobMatcher};
use ignore::{WalkBuilder, WalkState};

use crate::config::expand;

const GLOB_CHARS: [char; 4] = ['*', '?', '[', '{'];
const SKIP_DIRS: [&str; 2] = ["node_modules", ".git"];

/// Existing paths for every entry, limited to `visible` trees (canonical
/// paths): plain paths as-is, globs expanded. Symlinks are resolved; missing
/// or invisible paths are skipped.
pub fn resolve(entries: &[String], home: &Path, visible: &[PathBuf]) -> Result<Vec<PathBuf>> {
    let is_visible = |p: &Path| visible.iter().any(|v| p.starts_with(v));
    let mut out = Vec::new();
    for entry in entries {
        let path = expand(entry, home);
        if !path.to_string_lossy().contains(GLOB_CHARS) {
            out.extend(path.canonicalize().ok().filter(|p| is_visible(p)));
            continue;
        }
        let (base, rest) = split_glob(&path);
        let matcher = GlobBuilder::new(&rest)
            .literal_separator(true)
            .build()
            .with_context(|| format!("invalid glob '{entry}'"))?
            .compile_matcher();
        let Ok(base) = base.canonicalize() else {
            continue;
        };
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
            out.extend(walk(root, &base, &matcher));
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

/// Paths below `root` whose path relative to `base` matches.
fn walk(root: &Path, base: &Path, matcher: &GlobMatcher) -> Vec<PathBuf> {
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
        let root = root.canonicalize().unwrap();
        let everything = resolve(&entries, home, std::slice::from_ref(&root)).unwrap();
        // only app/pkg visible (like a project): nothing outside it is walked
        let pkg_only = resolve(&entries, home, &[root.join("app/pkg")]).unwrap();
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(
            everything,
            [
                root.join("app/.env"),
                root.join("app/pkg/.env"),
                root.join("secret-dir")
            ]
        );
        assert_eq!(pkg_only, [root.join("app/pkg/.env")]);
    }
}
