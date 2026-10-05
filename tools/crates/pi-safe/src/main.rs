//! pi-safe: run pi inside a bubblewrap + pasta sandbox.
//!
//! This binary only decides *what* the sandbox looks like (config, path
//! resolution, hidden files) and then execs `pasta -- bwrap ... -- pi`. The
//! isolation itself is done by those two, which Ubuntu ships with AppArmor
//! profiles allowing unprivileged user namespaces.

mod config;
mod hide;
mod ports;
mod probe;
mod sandbox;

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::io::Write as _;
use std::os::unix::fs::MetadataExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

use anyhow::{Context, Result};
use clap::Parser;

use config::{Config, NetMode, expand};
use sandbox::{Ctx, Mount, State};

/// Run pi in a sandbox that sees only the current project (read-write, .git
/// read-only); --context adds ~/repos and ~/share read-only. .env files,
/// secrets in $HOME, docker and the VM's localhost are hidden.
#[derive(Parser)]
#[command(
    name = "pi-safe",
    after_help = "Arguments after the options go to pi: `pi-safe -p \"hi\"`, `pi-safe -- --help`.\n\
                  Config: ~/.config/pi-safe/config.toml"
)]
struct Cli {
    /// Allow the VM's localhost:PORT from inside the sandbox (repeatable)
    #[arg(long = "port", value_name = "PORT")]
    ports: Vec<u16>,
    /// Publish sandbox PORT on the VM, e.g. a dev server (repeatable)
    #[arg(long = "publish", value_name = "PORT")]
    publish: Vec<u16>,
    /// Network mode, overriding the config
    #[arg(long, value_enum)]
    net: Option<NetMode>,
    /// Run leak tests inside the sandbox instead of pi
    #[arg(long, conflicts_with = "shell")]
    check: bool,
    /// Open bash inside the sandbox instead of pi
    #[arg(long)]
    shell: bool,
    /// Also mount the `filesystem.context` trees read-only (~/repos, ~/share)
    #[arg(long)]
    context: bool,
    /// Print the sandbox summary and command without running it
    #[arg(long)]
    dry_run: bool,
    /// Config file [default: ~/.config/pi-safe/config.toml]
    #[arg(long, value_name = "FILE")]
    config: Option<PathBuf>,
    /// Arguments for pi
    #[arg(
        trailing_var_arg = true,
        allow_hyphen_values = true,
        value_name = "PI_ARGS"
    )]
    args: Vec<String>,
}

fn main() -> ExitCode {
    // `--check` re-runs this binary inside the sandbox as `__probe <expect>`
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some(probe::ARG) {
        return probe::run(args.get(2).map_or("", String::as_str));
    }
    match run(Cli::parse()) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("pi-safe: {e:#}");
            ExitCode::from(2)
        }
    }
}

fn run(cli: Cli) -> Result<ExitCode> {
    let home = PathBuf::from(std::env::var_os("HOME").context("HOME is not set")?);
    let config_path = cli
        .config
        .clone()
        .unwrap_or_else(|| Config::default_path(&home));
    let mut cfg = Config::load(&config_path, cli.config.is_some())?;

    let cwd = std::env::current_dir()?.canonicalize()?;
    let project = project_root(&cwd);
    // broad dirs would expose many repos rw; ancestors of $HOME the real home
    let denied = cfg.denied_by(&project, &home)?;
    if denied.is_some() || home.starts_with(&project) {
        let why = denied
            .map(|d| format!(" (deny_projects: {d})"))
            .unwrap_or_default();
        eprintln!(
            "pi-safe: refusing to make '{}' writable{why} - run it inside a project",
            project.display()
        );
        return Ok(ExitCode::from(1));
    }

    cfg.network.host_ports.extend(&cli.ports);
    cfg.network.publish_ports.extend(&cli.publish);
    if let Some(n) = cli.net {
        cfg.network.mode = n;
    }
    let tool = cfg.command.first().cloned().unwrap_or_default();
    if cli.check {
        // placeholder; the real probe arguments need the finished plan
        cfg.command = vec![probe::SANDBOX_PATH.into()];
    } else if cli.shell {
        // the prompt shows the sandbox via its hostname: user@pi-safe
        cfg.command = vec!["bash".into()];
    } else {
        cfg.command.extend(cli.args);
    }

    let state_dir = expand(&cfg.state_dir, &home);
    let state = State::new(&state_dir);
    prepare_state(&state)?;

    if cli.context {
        let context = std::mem::take(&mut cfg.filesystem.context);
        cfg.filesystem.read_only.extend(context);
    }
    let mut visible = vec![project.clone()];
    for p in cfg
        .filesystem
        .read_only
        .iter()
        .chain(&cfg.filesystem.read_write)
    {
        visible.extend(expand(p, &home).canonicalize().ok());
    }
    let hidden = hide::resolve(&cfg.filesystem.hidden, &home, &visible)?;

    let me = std::fs::metadata("/proc/self").context("cannot stat /proc/self")?;
    let ctx = Ctx {
        user: std::env::var("USER").unwrap_or_else(|_| "user".into()),
        uid: me.uid(),
        gid: me.gid(),
        cwd,
        git_common_dir: git_common_dir(&project),
        caller_path: std::env::var("PATH").unwrap_or_default(),
        caller_env: std::env::vars().collect::<BTreeMap<_, _>>(),
        project: project.clone(),
        home: home.clone(),
    };
    let mut plan = sandbox::build(&cfg, &ctx, &state, &hidden)?;

    if cli.check {
        let expect = expectations(&cfg, &plan, &project, &home, &hidden, tool)?;
        let exe = std::env::current_exe().context("cannot locate own binary")?;
        plan.mounts.push(Mount::Ro(exe, probe::SANDBOX_PATH.into()));
        plan.command = vec![
            probe::SANDBOX_PATH.into(),
            probe::ARG.into(),
            toml::to_string(&expect)?,
        ];
    }

    if plan.net == NetMode::Host {
        eprintln!("pi-safe: WARNING - network 'host' exposes every localhost service of the VM");
    }
    let argv = plan.argv();
    if cli.dry_run {
        let mut out = String::new();
        writeln!(out, "project   {}", project.display())?;
        writeln!(
            out,
            "network   {:?}  host ports {:?}  published {:?}",
            plan.net, plan.host_ports, plan.publish_ports
        )?;
        writeln!(out, "hidden    {} path(s)", hidden.len())?;
        for h in &hidden {
            writeln!(out, "          {}", h.display())?;
        }
        writeln!(out, "\n{}", sandbox::quote(&argv))?;
        // ignore EPIPE: `pi-safe --dry-run | head` is a normal use
        let _ = std::io::stdout().write_all(out.as_bytes());
        return Ok(ExitCode::SUCCESS);
    }

    let err = Command::new(&argv[0]).args(&argv[1..]).exec();
    Err(err).with_context(|| format!("cannot run {}", argv[0].to_string_lossy()))
}

/// What `--check` expects to find inside the sandbox.
fn expectations(
    cfg: &Config,
    plan: &sandbox::Plan,
    project: &Path,
    home: &Path,
    hidden: &[PathBuf],
    command: String,
) -> Result<probe::Expect> {
    let (mut pi_writable, mut pi_read_only) = (Vec::new(), Vec::new());
    let agent = expand(&cfg.pi.agent_dir, home);
    if let Ok(real) = agent.canonicalize() {
        let (shared, local) = (
            sandbox::globs(&cfg.pi.shared)?,
            sandbox::globs(&cfg.pi.local)?,
        );
        for entry in std::fs::read_dir(real)?.flatten() {
            let name = entry.file_name();
            if shared.is_match(&name) {
                pi_writable.push(agent.join(&name));
            } else if !local.is_match(&name) {
                pi_read_only.push(agent.join(&name));
            }
        }
    }

    Ok(probe::Expect {
        project: project.to_path_buf(),
        project_read_only: cfg
            .filesystem
            .project_read_only
            .iter()
            .map(|p| project.join(p))
            .collect(),
        read_only: plan.read_only.clone(),
        hidden: hidden.to_vec(),
        pi_writable,
        pi_read_only,
        command,
        listening: ports::listening(),
        allowed_ports: plan.host_ports.clone(),
        internet: plan.net != NetMode::None,
    })
}

/// The git top-level of `cwd`, else `cwd` itself.
fn project_root(cwd: &Path) -> PathBuf {
    git(cwd, &["rev-parse", "--show-toplevel"])
        .and_then(|p| PathBuf::from(p).canonicalize().ok())
        .unwrap_or_else(|| cwd.to_path_buf())
}

/// Where a worktree keeps its objects, refs and config.
fn git_common_dir(project: &Path) -> Option<PathBuf> {
    git(
        project,
        &["rev-parse", "--path-format=absolute", "--git-common-dir"],
    )
    .and_then(|p| PathBuf::from(p).canonicalize().ok())
}

fn git(dir: &Path, args: &[&str]) -> Option<String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Creates the sandbox home and the small files the mount plan points at.
fn prepare_state(state: &State) -> Result<()> {
    let run = state.resolv_conf.parent().expect("state run dir");
    let caches = sandbox::TMP_CACHES.map(|c| state.tmp_cache.join(c));
    for d in [&state.home, &state.empty_dir, &run.to_path_buf()]
        .into_iter()
        .chain(&caches)
    {
        std::fs::create_dir_all(d).with_context(|| format!("cannot create {}", d.display()))?;
    }
    std::fs::write(&state.empty_file, "")?;
    std::fs::write(&state.resolv_conf, format!("nameserver {}\n", sandbox::DNS))?;
    Ok(())
}
