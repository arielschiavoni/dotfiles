//! Turns the config into a bwrap mount plan plus the pasta wrapper.
//!
//! bwrap applies mounts in order, later ones on top of earlier ones, so the
//! order below is the security model:
//!
//!   1. system dirs read-only, fresh /proc /dev /tmp /run, persistent
//!      sandbox-only compile caches in /tmp
//!   2. a sandbox-only $HOME (state dir), so the real home is invisible
//!   3. configured read-only / read-write trees (~/repos, mise, ...)
//!   4. pi's agent dir: read-only except the shared entries
//!   5. the project read-write, then its read-only parts (.git)
//!   6. hidden paths (e.g. every .env), covered with empty ones
//!
//! The project is writable whatever it is - the dotfiles repo included, even
//! though pi's agent dir and pi-safe's config live there.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use globset::{Glob, GlobSet, GlobSetBuilder};

use crate::config::{Config, NetMode, Pi, expand};

/// pasta's DNS forwarder address inside the namespace.
pub const DNS: &str = "169.254.1.1";

/// Compile caches node tools keep in /tmp. /tmp is a fresh tmpfs, so without
/// these pi re-transpiles its TypeScript extensions (jiti) on every start:
/// ~2.2s instead of ~0.5s. They persist in the state dir, never shared with
/// the host's /tmp: plain pi must not load code compiled inside the sandbox.
pub const TMP_CACHES: [&str; 2] = ["jiti", "node-compile-cache"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mount {
    Ro(PathBuf, PathBuf),
    Rw(PathBuf, PathBuf),
    Tmpfs(PathBuf),
    Symlink(PathBuf, PathBuf),
    Proc(PathBuf),
    Dev(PathBuf),
    /// Cover a file or dir with an empty read-only one.
    Hide(PathBuf, bool),
}

/// Everything about the caller that the plan depends on.
pub struct Ctx {
    pub home: PathBuf,
    pub user: String,
    pub uid: u32,
    pub gid: u32,
    pub cwd: PathBuf,
    pub project: PathBuf,
    pub git_common_dir: Option<PathBuf>,
    pub caller_path: String,
    pub caller_env: BTreeMap<String, String>,
}

/// Paths inside the state dir; see `prepare_state` in main.rs.
pub struct State {
    pub home: PathBuf,
    pub resolv_conf: PathBuf,
    pub empty_file: PathBuf,
    pub empty_dir: PathBuf,
    /// Parent of the `TMP_CACHES` dirs.
    pub tmp_cache: PathBuf,
}

impl State {
    pub fn new(dir: &Path) -> Self {
        let run = dir.join("run");
        Self {
            home: dir.join("home"),
            resolv_conf: run.join("resolv.conf"),
            empty_file: run.join("empty"),
            empty_dir: run.join("empty.d"),
            tmp_cache: dir.join("tmp-cache"),
        }
    }
}

pub struct Plan {
    pub mounts: Vec<Mount>,
    pub env: Vec<(String, String)>,
    pub net: NetMode,
    pub host_ports: Vec<u16>,
    pub publish_ports: Vec<u16>,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub uid: u32,
    pub gid: u32,
    pub empty_file: PathBuf,
    pub empty_dir: PathBuf,
    /// Read-only trees, for `--check`.
    pub read_only: Vec<PathBuf>,
}

/// `hidden`: existing paths from `hide::resolve`.
pub fn build(cfg: &Config, ctx: &Ctx, state: &State, hidden: &[PathBuf]) -> Result<Plan> {
    let home = &ctx.home;
    let mut m = system_mounts(cfg.network.mode, state)?;

    // 2. sandbox home
    m.push(Mount::Rw(state.home.clone(), home.clone()));

    // 3. configured trees, parents before children so nesting works
    let mut trees: Vec<(PathBuf, PathBuf, bool)> = Vec::new();
    for (list, rw) in [
        (&cfg.filesystem.read_only, false),
        (&cfg.filesystem.read_write, true),
    ] {
        for p in list {
            let dest = expand(p, home);
            if let Ok(src) = fs::canonicalize(&dest) {
                trees.push((src, dest, rw));
            }
        }
    }
    trees.sort_by_key(|(_, dest, rw)| (dest.components().count(), *rw));
    // a project in $HOME outside every tree (e.g. ~/repos left out of read_only)
    // needs its parent dirs created as mount points; keep them on a tmpfs, not
    // in the persistent sandbox home where they would pile up
    if let Some(top) = scratch_parent(&ctx.project, home, &trees) {
        m.push(Mount::Tmpfs(top));
    }
    for (src, dest, rw) in &trees {
        m.push(if *rw {
            Mount::Rw(src.clone(), dest.clone())
        } else {
            Mount::Ro(src.clone(), dest.clone())
        });
    }

    // 4. pi agent dir
    let agent_dest = expand(&cfg.pi.agent_dir, home);
    let agent_real = fs::canonicalize(&agent_dest).ok();
    if let Some(real) = &agent_real {
        m.extend(agent_mounts(real, &agent_dest, &cfg.pi)?);
    }

    // 5. project
    let project = &ctx.project;
    m.push(Mount::Rw(project.clone(), project.clone()));
    for rel in &cfg.filesystem.project_read_only {
        let p = project.join(rel);
        if p.exists() {
            m.push(Mount::Ro(p.clone(), p));
        }
    }
    if let Some(common) = &ctx.git_common_dir
        && !common.starts_with(project)
    {
        m.push(Mount::Ro(common.clone(), common.clone()));
    }

    // 6. hidden paths. Anything below an already hidden dir is skipped: it
    //    no longer exists to be mounted over.
    if let Some(h) = hidden.iter().find(|h| project.starts_with(h)) {
        bail!(
            "'{}' is hidden by the config but contains the project",
            h.display()
        );
    }
    m.extend(hide_mounts(
        hidden.iter().map(|h| (h.clone(), h.is_dir())).collect(),
    ));

    // environment: allowlist only
    let mut visible: Vec<PathBuf> = ["/usr", "/bin", "/sbin", "/opt"]
        .iter()
        .map(PathBuf::from)
        .collect();
    visible.extend(trees.iter().map(|t| t.1.clone()));
    visible.push(project.clone());
    let path = filter_path(&ctx.caller_path, &visible);
    let mut env = vec![
        ("HOME".to_string(), home.display().to_string()),
        ("USER".to_string(), ctx.user.clone()),
        ("LOGNAME".to_string(), ctx.user.clone()),
        ("PATH".to_string(), path.clone()),
    ];
    for name in &cfg.env.pass {
        if let Some(v) = ctx.caller_env.get(name) {
            env.push((name.clone(), v.clone()));
        }
    }
    env.extend(cfg.env.set.iter().map(|(k, v)| (k.clone(), v.clone())));

    let command = cfg.command.clone();
    let Some(prog) = command.first() else {
        bail!("empty command")
    };
    if !prog.contains('/') && find_in_path(prog, &path).is_none() {
        bail!("'{prog}' is not on the sandbox PATH (only system dirs and visible trees are kept)");
    }

    Ok(Plan {
        mounts: m,
        env,
        net: cfg.network.mode,
        host_ports: cfg.network.host_ports.clone(),
        publish_ports: cfg.network.publish_ports.clone(),
        command,
        cwd: ctx.cwd.clone(),
        uid: ctx.uid,
        gid: ctx.gid,
        empty_file: state.empty_file.clone(),
        empty_dir: state.empty_dir.clone(),
        read_only: trees.iter().filter(|t| !t.2).map(|t| t.1.clone()).collect(),
    })
}

/// The first dir below $HOME on the way to the project (`~/repos`), when no
/// tree already covers the project.
fn scratch_parent(
    project: &Path,
    home: &Path,
    trees: &[(PathBuf, PathBuf, bool)],
) -> Option<PathBuf> {
    let rel = project.strip_prefix(home).ok()?;
    let top = home.join(rel.components().next()?);
    let covered = trees.iter().any(|(_, dest, _)| project.starts_with(dest));
    (!covered && top != project).then_some(top)
}

/// One `Hide` per path, minus paths inside a hidden dir.
fn hide_mounts(mut hidden: Vec<(PathBuf, bool)>) -> Vec<Mount> {
    hidden.sort();
    hidden.dedup();
    let mut dirs: Vec<PathBuf> = Vec::new();
    let mut m = Vec::new();
    for (p, is_dir) in hidden {
        if dirs.iter().any(|d| p.starts_with(d)) {
            continue;
        }
        if is_dir {
            dirs.push(p.clone());
        }
        m.push(Mount::Hide(p, is_dir));
    }
    m
}

fn system_mounts(net: NetMode, state: &State) -> Result<Vec<Mount>> {
    let mut m = vec![
        Mount::Ro("/usr".into(), "/usr".into()),
        Mount::Ro("/etc".into(), "/etc".into()),
    ];
    for d in ["/bin", "/sbin", "/lib", "/lib64", "/lib32", "/opt"] {
        match fs::symlink_metadata(d) {
            Ok(md) if md.is_symlink() => m.push(Mount::Symlink(fs::read_link(d)?, d.into())),
            Ok(md) if md.is_dir() => m.push(Mount::Ro(d.into(), d.into())),
            _ => {}
        }
    }
    m.push(Mount::Proc("/proc".into()));
    m.push(Mount::Dev("/dev".into()));
    for t in ["/tmp", "/var/tmp", "/run"] {
        m.push(Mount::Tmpfs(t.into()));
    }
    for c in TMP_CACHES {
        m.push(Mount::Rw(
            state.tmp_cache.join(c),
            Path::new("/tmp").join(c),
        ));
    }
    // /etc/resolv.conf usually points into /run, which is now empty
    let resolv = fs::canonicalize("/etc/resolv.conf").context("cannot resolve /etc/resolv.conf")?;
    match net {
        NetMode::Pasta => m.push(Mount::Ro(state.resolv_conf.clone(), resolv)),
        NetMode::Host => m.push(Mount::Ro(resolv.clone(), resolv)),
        NetMode::None => {}
    }
    Ok(m)
}

/// The agent dir mirrored at `dest`: shared entries read-write, local ones
/// left out (they live in the sandbox home), the rest read-only.
fn agent_mounts(real: &Path, dest: &Path, pi: &Pi) -> Result<Vec<Mount>> {
    let shared = globs(&pi.shared)?;
    let local = globs(&pi.local)?;
    let mut names: Vec<OsString> = fs::read_dir(real)
        .with_context(|| format!("cannot read {}", real.display()))?
        .filter_map(|e| e.ok().map(|e| e.file_name()))
        .collect();
    names.sort();
    let mut m = Vec::new();
    for name in names {
        let (src, dst) = (real.join(&name), dest.join(&name));
        if shared.is_match(&name) {
            m.push(Mount::Rw(src, dst));
        } else if !local.is_match(&name) {
            m.push(Mount::Ro(src, dst));
        }
    }
    Ok(m)
}

pub fn globs(patterns: &[String]) -> Result<GlobSet> {
    let mut b = GlobSetBuilder::new();
    for p in patterns {
        b.add(Glob::new(p).with_context(|| format!("invalid glob '{p}'"))?);
    }
    Ok(b.build()?)
}

/// Caller PATH entries that exist inside the sandbox, deduplicated.
fn filter_path(path: &str, visible: &[PathBuf]) -> String {
    let mut out: Vec<&str> = Vec::new();
    for p in path.split(':') {
        if !p.is_empty() && visible.iter().any(|v| Path::new(p).starts_with(v)) && !out.contains(&p)
        {
            out.push(p);
        }
    }
    out.join(":")
}

fn find_in_path(prog: &str, path: &str) -> Option<PathBuf> {
    path.split(':').map(|d| Path::new(d).join(prog)).find(|p| {
        p.metadata()
            .is_ok_and(|md| md.is_file() && md.permissions().mode() & 0o111 != 0)
    })
}

fn ports(p: &[u16]) -> String {
    if p.is_empty() {
        "none".into()
    } else {
        p.iter().map(u16::to_string).collect::<Vec<_>>().join(",")
    }
}

impl Plan {
    /// Full argv: `[pasta ... --] bwrap ... -- command...`
    pub fn argv(&self) -> Vec<OsString> {
        let mut a = Args::default();
        if self.net == NetMode::Pasta {
            a.str(&[
                "pasta",
                "--quiet",
                "--config-net",
                "--no-map-gw",
                "--dns-forward",
                DNS,
            ]);
            a.str(&["-t", &ports(&self.publish_ports), "-u", "none"]);
            a.str(&["-T", &ports(&self.host_ports), "-U", "none", "--"]);
        }
        a.str(&[
            "bwrap",
            "--unshare-all",
            "--unshare-user",
            "--disable-userns",
            "--die-with-parent",
        ]);
        a.str(&[
            "--hostname",
            "pi-safe",
            "--uid",
            &self.uid.to_string(),
            "--gid",
            &self.gid.to_string(),
        ]);
        if self.net != NetMode::None {
            // pasta already created the netns; host mode wants the VM's
            a.str(&["--share-net"]);
        }
        for mount in &self.mounts {
            match mount {
                Mount::Ro(s, d) => a.paths("--ro-bind", &[s, d]),
                Mount::Rw(s, d) => a.paths("--bind", &[s, d]),
                Mount::Symlink(t, l) => a.paths("--symlink", &[t, l]),
                Mount::Tmpfs(d) => a.paths("--tmpfs", &[d]),
                Mount::Proc(d) => a.paths("--proc", &[d]),
                Mount::Dev(d) => a.paths("--dev", &[d]),
                Mount::Hide(d, is_dir) => {
                    let src = if *is_dir {
                        &self.empty_dir
                    } else {
                        &self.empty_file
                    };
                    a.paths("--ro-bind", &[src, d]);
                }
            }
        }
        a.str(&["--clearenv"]);
        for (k, v) in &self.env {
            a.str(&["--setenv", k, v]);
        }
        a.paths("--chdir", &[&self.cwd]);
        a.str(&["--"]);
        a.0.extend(self.command.iter().map(OsString::from));
        a.0
    }
}

#[derive(Default)]
struct Args(Vec<OsString>);

impl Args {
    fn str(&mut self, items: &[&str]) {
        self.0.extend(items.iter().map(OsString::from));
    }

    fn paths(&mut self, flag: &str, paths: &[&PathBuf]) {
        self.0.push(flag.into());
        self.0
            .extend(paths.iter().map(|p| p.as_os_str().to_os_string()));
    }
}

/// Shell-quoted argv, for `--dry-run`.
pub fn quote(argv: &[OsString]) -> String {
    argv.iter()
        .map(|a| {
            let s = a.to_string_lossy();
            if !s.is_empty()
                && s.chars()
                    .all(|c| c.is_ascii_alphanumeric() || "_-./:=,@%+".contains(c))
            {
                s.into_owned()
            } else {
                format!("'{}'", s.replace('\'', r"'\''"))
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filters_path_to_visible_dirs() {
        let visible = [
            PathBuf::from("/usr"),
            PathBuf::from("/home/u/.local/share/mise"),
        ];
        let path = "/home/u/.cargo/bin:/home/u/.local/share/mise/installs/node/bin:/usr/bin:/usr/bin:/snap/bin";
        assert_eq!(
            filter_path(path, &visible),
            "/home/u/.local/share/mise/installs/node/bin:/usr/bin"
        );
    }

    #[test]
    fn scratch_parent_only_when_project_is_uncovered() {
        let home = Path::new("/h");
        let project = Path::new("/h/repos/org/app");
        let tree = |d: &str| (PathBuf::from(d), PathBuf::from(d), false);
        assert_eq!(
            scratch_parent(project, home, &[tree("/h/.config/git")]),
            Some("/h/repos".into())
        );
        assert_eq!(scratch_parent(project, home, &[tree("/h/repos")]), None);
        assert_eq!(scratch_parent(Path::new("/tmp/x"), home, &[]), None);
        assert_eq!(scratch_parent(Path::new("/h/app"), home, &[]), None);
    }

    #[test]
    fn hiding_a_dir_drops_hides_inside_it() {
        let m = hide_mounts(vec![
            ("/r/b/.env".into(), false),
            ("/r/a/x/.env".into(), false),
            ("/r/a".into(), true),
            ("/r/ab/.env".into(), false),
        ]);
        assert_eq!(
            m,
            [
                Mount::Hide("/r/a".into(), true),
                Mount::Hide("/r/ab/.env".into(), false),
                Mount::Hide("/r/b/.env".into(), false),
            ]
        );
    }

    #[test]
    fn quotes_only_when_needed() {
        let argv: Vec<OsString> = ["bwrap", "--setenv", "A", "x y", "it's"]
            .iter()
            .map(OsString::from)
            .collect();
        assert_eq!(quote(&argv), r"bwrap --setenv A 'x y' 'it'\''s'");
    }

    #[test]
    fn pasta_wraps_bwrap_with_port_allowlist() {
        let plan = Plan {
            mounts: vec![Mount::Hide("/p/.env".into(), false)],
            env: vec![("PATH".into(), "/usr/bin".into())],
            net: NetMode::Pasta,
            host_ports: vec![3000, 5432],
            publish_ports: vec![],
            command: vec!["pi".into(), "-p".into()],
            cwd: "/p".into(),
            uid: 501,
            gid: 1000,
            empty_file: "/s/empty".into(),
            empty_dir: "/s/empty.d".into(),
            read_only: vec![],
        };
        let q = quote(&plan.argv());
        assert!(q.starts_with("pasta --quiet --config-net --no-map-gw --dns-forward 169.254.1.1 -t none -u none -T 3000,5432 -U none -- bwrap"));
        assert!(q.contains("--share-net --ro-bind /s/empty /p/.env --clearenv --setenv PATH /usr/bin --chdir /p -- pi -p"));
    }
}
