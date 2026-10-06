//! `~/.config/pi-safe/config.toml`: every field is optional and falls back to
//! the defaults below. Lists in the file *replace* the default list.
//!
//! Config is only ever read from the user's config dir, never from the
//! project: the sandboxed agent can write to the project, and must not be able
//! to widen its own sandbox for the next run.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use globset::{GlobBuilder, GlobMatcher};
use serde::Deserialize;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize, clap::ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum NetMode {
    /// Own network namespace via pasta: internet yes, VM localhost no
    #[default]
    Pasta,
    /// Share the VM's network, including every localhost service (unsafe)
    Host,
    /// No network at all
    None,
}

#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// What runs inside the sandbox; CLI args are appended.
    pub command: Vec<String>,
    /// Sandbox-only state: its $HOME (caches, history), resolv.conf.
    pub state_dir: String,
    /// Globs for directories that must never be the project root.
    pub deny_projects: Vec<String>,
    pub network: Network,
    pub filesystem: Filesystem,
    pub pi: Pi,
    pub env: Env,
    pub broker: Broker,
}

#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Network {
    pub mode: NetMode,
    /// VM localhost ports reachable from inside the sandbox (pasta -T).
    pub host_ports: Vec<u16>,
    /// Sandbox ports published on the VM, e.g. a dev server the agent starts
    /// that the Mac browser should reach (pasta -t).
    pub publish_ports: Vec<u16>,
}

#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Filesystem {
    /// Visible read-only (besides /usr, /etc, ...). Symlinks are resolved.
    pub read_only: Vec<String>,
    /// Extra read-only trees mounted only with `--context`, for giving the
    /// agent other projects to read. Off by default: faster, and the agent
    /// sees only the project.
    pub context: Vec<String>,
    /// Visible read-write, in addition to the project.
    pub read_write: Vec<String>,
    /// Hidden even inside a visible tree: dirs show up empty, files empty.
    /// Paths or globs (`*` stays within one dir, `**` crosses dirs); globs are
    /// resolved at start, skipping node_modules and .git.
    pub hidden: Vec<String>,
    /// Paths relative to the project root kept read-only.
    pub project_read_only: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Pi {
    pub agent_dir: String,
    /// Entries (name globs) shared read-write with the unsandboxed pi.
    pub shared: Vec<String>,
    /// Entries (name globs) that stay sandbox-local: written inside, never
    /// seen by the unsandboxed pi. Everything else is read-only.
    pub local: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Env {
    /// Variables passed through from the caller; everything else is dropped.
    pub pass: Vec<String>,
    /// Fixed variables.
    pub set: BTreeMap<String, String>,
}

/// The credential broker: cred-broker, a proxy on the VM that puts the real
/// tokens into the sandbox's requests, so the sandbox only holds placeholders.
/// Its port, rules and token sources are in its own config
/// (~/.config/cred-broker/config.toml).
#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Broker {
    pub enabled: bool,
    /// The cred-broker program (pi-safe appends `start`, `status --json`).
    pub command: Vec<String>,
    /// pi OAuth logins the broker serves; the sandbox's auth.json gets
    /// placeholders for them and drops every other entry.
    pub providers: Vec<String>,
    /// Variables set to the placeholder, for tools that need a token to be
    /// present at all (gh, the Jira skill).
    pub placeholder_env: Vec<String>,
}

fn strings(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| s.to_string()).collect()
}

impl Default for Config {
    fn default() -> Self {
        Self {
            command: strings(&["pi"]),
            state_dir: "~/.local/state/pi-safe".into(),
            deny_projects: strings(&[
                "/",
                "/home",
                "~",
                "~/repos",
                "~/repos/*",
                "~/share",
                "/tmp",
                "/var/tmp",
                "/dev/shm",
            ]),
            network: Network::default(),
            filesystem: Filesystem::default(),
            pi: Pi::default(),
            env: Env::default(),
            broker: Broker::default(),
        }
    }
}

impl Default for Broker {
    fn default() -> Self {
        Self {
            enabled: false,
            command: strings(&["cred-broker"]),
            providers: strings(&["github-copilot", "anthropic"]),
            placeholder_env: strings(&["GITHUB_TOKEN", "JIRA_PAT_TOKEN"]),
        }
    }
}

impl Default for Network {
    fn default() -> Self {
        Self {
            mode: NetMode::Pasta,
            host_ports: Vec::new(),
            publish_ports: Vec::new(),
        }
    }
}

impl Default for Filesystem {
    fn default() -> Self {
        Self {
            read_only: strings(&[
                "~/.local/share/mise",
                "~/.config/mise",
                "~/.config/git",
                "~/.agents",
                "~/.config/opencode/skills",
            ]),
            context: strings(&["~/repos", "~/share"]),
            read_write: Vec::new(),
            hidden: strings(&["~/repos/**/.env", "~/share/**/.env"]),
            project_read_only: strings(&[".git"]),
        }
    }
}

impl Default for Pi {
    fn default() -> Self {
        Self {
            agent_dir: "~/.pi/agent".into(),
            shared: strings(&[
                "auth.json",
                "mcp-auth.json",
                "sessions",
                "settings.json",
                "trust.json",
            ]),
            local: strings(&["mcp.log*", "models-store.json", "*.lock", ".gitignore"]),
        }
    }
}

impl Default for Env {
    fn default() -> Self {
        Self {
            pass: strings(&[
                "TERM",
                "COLORTERM",
                "TERM_PROGRAM",
                "TERM_PROGRAM_VERSION",
                "LANG",
                "LC_ALL",
                "LC_CTYPE",
                "TZ",
                "EDITOR",
                "VISUAL",
            ]),
            set: BTreeMap::from([("PI_SAFE".to_string(), "1".to_string())]),
        }
    }
}

impl Config {
    /// Default location: `$XDG_CONFIG_HOME/pi-safe/config.toml`.
    pub fn default_path(home: &Path) -> PathBuf {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".config"));
        base.join("pi-safe/config.toml")
    }

    /// Loads `path`; a missing file at the default location means defaults.
    pub fn load(path: &Path, explicit: bool) -> Result<Self> {
        match std::fs::read_to_string(path) {
            Ok(text) => Self::parse(&text).with_context(|| format!("invalid {}", path.display())),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound && !explicit => Ok(Self::default()),
            Err(e) => Err(e).with_context(|| format!("cannot read {}", path.display())),
        }
    }

    pub fn parse(text: &str) -> Result<Self> {
        Ok(toml::from_str(text)?)
    }

    /// The first `deny_projects` glob matching `project`, if any.
    pub fn denied_by(&self, project: &Path, home: &Path) -> Result<Option<String>> {
        for pattern in &self.deny_projects {
            if glob(pattern, home)?.is_match(project) {
                return Ok(Some(pattern.clone()));
            }
        }
        Ok(None)
    }
}

/// `~` and `~/x` relative to `home`; everything else unchanged.
pub fn expand(path: &str, home: &Path) -> PathBuf {
    match path.strip_prefix('~') {
        Some("") => home.to_path_buf(),
        Some(rest) if rest.starts_with('/') => home.join(&rest[1..]),
        _ => PathBuf::from(path),
    }
}

/// A path glob where `*` does not cross `/`.
fn glob(pattern: &str, home: &Path) -> Result<GlobMatcher> {
    let expanded = expand(pattern, home);
    let glob = GlobBuilder::new(&expanded.to_string_lossy())
        .literal_separator(true)
        .build()
        .with_context(|| format!("invalid glob '{pattern}'"))?;
    Ok(glob.compile_matcher())
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOME: &str = "/home/u";

    #[test]
    fn expands_tilde() {
        let h = Path::new(HOME);
        assert_eq!(expand("~", h), PathBuf::from("/home/u"));
        assert_eq!(expand("~/repos", h), PathBuf::from("/home/u/repos"));
        assert_eq!(expand("~other", h), PathBuf::from("~other"));
        assert_eq!(expand("/tmp", h), PathBuf::from("/tmp"));
    }

    #[test]
    fn empty_file_is_defaults() {
        let c = Config::parse("").unwrap();
        assert_eq!(c.command, ["pi"]);
        assert_eq!(c.network.mode, NetMode::Pasta);
        assert!(!c.filesystem.read_only.contains(&"~/repos".to_string()));
        assert_eq!(c.filesystem.context, ["~/repos", "~/share"]);
    }

    #[test]
    fn shipped_config_parses() {
        let text = include_str!("../../../../config/pi-safe/.config/pi-safe/config.toml");
        // uncommenting the documented defaults must still parse
        let is_toml = |r: &&str| {
            r.starts_with(['[', ']']) || r.starts_with("  \"") || {
                let key = r.split(" = ").next().unwrap_or_default();
                r.contains(" = ") && key.chars().all(|c| c.is_ascii_lowercase() || c == '_')
            }
        };
        let uncommented: String = text
            .lines()
            .map(|l| l.strip_prefix("# ").filter(is_toml).unwrap_or(l))
            .collect::<Vec<_>>()
            .join("\n");
        Config::parse(text).unwrap();
        Config::parse(&uncommented).unwrap();
    }

    #[test]
    fn rejects_unknown_keys() {
        assert!(Config::parse("[network]\nhost_port = [1]").is_err());
    }

    #[test]
    fn deny_globs_do_not_cross_slashes() {
        let h = Path::new(HOME);
        let c = Config::default();
        assert!(c.denied_by(Path::new("/home/u"), h).unwrap().is_some());
        assert!(
            c.denied_by(Path::new("/home/u/repos/org"), h)
                .unwrap()
                .is_some()
        );
        assert!(c.denied_by(Path::new("/tmp"), h).unwrap().is_some());
        assert!(
            c.denied_by(Path::new("/home/u/repos/org/app"), h)
                .unwrap()
                .is_none()
        );
        assert!(c.denied_by(Path::new("/tmp/x"), h).unwrap().is_none());
    }
}
