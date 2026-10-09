//! pi-safe: run pi inside a bubblewrap + pasta sandbox.
//!
//! This binary only decides *what* the sandbox looks like (config, path
//! resolution, hidden files) and then execs `pasta -- bwrap ... -- pi`. The
//! isolation itself is done by those two, which Ubuntu ships with AppArmor
//! profiles allowing unprivileged user namespaces.

mod aws;
mod broker;
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

/// Run pi in a sandbox that sees the current project (read-write, .git
/// read-only) and ~/repos (read-only). .env files and other secrets, $HOME,
/// docker and the VM's localhost are hidden.
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
    // the sandbox's AWS credential_process
    if args.get(1).map(String::as_str) == Some(aws::ARG) {
        return aws::run(&args[2..]);
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
    let agent_dir = expand(&cfg.pi.agent_dir, &home);
    let state_dir = expand(&cfg.state_dir, &home);

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
    // the credential broker: started now (it outlives the sandbox), as its
    // port must be in the sandbox's allowlist
    let broker = (cfg.broker.enabled && cfg.network.mode != NetMode::None)
        .then(|| broker::Broker::new(&cfg.broker, &agent_dir));
    let broker_info = match &broker {
        Some(b) if cli.dry_run => Some(b.status()?),
        Some(b) => Some(b.start().context("credential broker")?),
        None => None,
    };
    if let Some(info) = &broker_info {
        // the real logins stay outside: hidden wherever a visible tree has
        // them (the dotfiles repo, where ~/.pi/agent is stowed from)
        if let Ok(real) = agent_dir.join("auth.json").canonicalize() {
            cfg.filesystem.hidden.push(real.display().to_string());
        }
        cfg.network.host_ports.push(info.port);
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

    let state = State::new(&state_dir);
    prepare_state(&state)?;

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

    let mut broker_note = "off".to_string();
    if let (Some(b), Some(info)) = (&broker, &broker_info) {
        broker_note = attach_broker(b, info, &mut plan, &state, &agent_dir, &project, &home)?;
    }

    if cli.check {
        let mut expect = expectations(&cfg, &plan, &project, &home, &hidden, tool)?;
        if let Some(info) = &broker_info {
            let auth = agent_dir.join("auth.json");
            // not shared with plain pi: the placeholder copy, checked there
            expect.pi_writable.retain(|p| *p != auth);
            expect.broker = Some(probe::BrokerExpect {
                auth,
                health: info.health.clone(),
            });
        }
        mount_self(&mut plan)?;
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
        writeln!(out, "broker    {broker_note}")?;
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

/// Routes the sandbox through the broker: placeholder auth.json, CA bundle,
/// proxy environment. Returns a one-line summary for `--dry-run`.
fn attach_broker(
    b: &broker::Broker,
    info: &broker::Info,
    plan: &mut sandbox::Plan,
    state: &State,
    agent_dir: &Path,
    project: &Path,
    home: &Path,
) -> Result<String> {
    let stub = state.resolv_conf.with_file_name("auth.json");
    let dropped = b.write_stub_auth(&stub)?;
    let dest = agent_dir.join("auth.json");
    // in place of the shared (real) auth.json, keeping the mount order
    match plan
        .mounts
        .iter_mut()
        .find(|m| matches!(m, Mount::Rw(_, d) | Mount::Ro(_, d) if *d == dest))
    {
        Some(m) => *m = Mount::Rw(stub, dest),
        None => plan.mounts.push(Mount::Rw(stub, dest)),
    }

    // a broker that never ran (--dry-run) has no CA yet
    let bundle = state.resolv_conf.with_file_name("ca-bundle.pem");
    match b.ca_bundle(info, &bundle) {
        Ok(()) => plan.mounts.push(Mount::Ro(bundle, broker::CA_DEST.into())),
        Err(e) if info.pid.is_none() => eprintln!("pi-safe: {e:#}"),
        Err(e) => return Err(e),
    }
    let org = broker::project_org(project, home);
    let mut env = b.env(&org, info.port);

    // AWS: the served profiles, with the broker as their credential_process
    if !info.aws_profiles.is_empty() {
        let real = aws_session::config::AwsConfig::load(&home.join(".aws"));
        let config = state.resolv_conf.with_file_name("aws-config");
        let text = aws::config_file(&info.aws_profiles, info.port, &real, probe::SANDBOX_PATH);
        std::fs::write(&config, text)
            .with_context(|| format!("cannot write {}", config.display()))?;
        plan.mounts
            .push(Mount::Ro(config, home.join(".aws/config")));
        mount_self(plan)?;
        // for the aws-profile pi extension, which asks which one to use
        env.push(("PI_SAFE_AWS_PROFILES".into(), info.aws_profiles.join(",")));
        // makes the JS SDK v2 read ~/.aws/config (credential_process)
        env.push(("AWS_SDK_LOAD_CONFIG".into(), "1".into()));
    }
    plan.env.retain(|(k, _)| !env.iter().any(|(e, _)| e == k));
    plan.env.extend(env);

    let mut note = match info.pid {
        Some(pid) => format!("cred-broker pid {pid}"),
        None => "cred-broker not running (starts with the sandbox)".into(),
    };
    write!(note, ", port {}, org hint {org}", info.port)?;
    if !dropped.is_empty() {
        write!(note, ", auth.json drops {}", dropped.join(" "))?;
    }
    if !info.aws_profiles.is_empty() {
        write!(note, ", aws {}", info.aws_profiles.join(" "))?;
    }
    Ok(note)
}

/// This binary inside the sandbox, for `--check` and AWS's credential_process.
fn mount_self(plan: &mut sandbox::Plan) -> Result<()> {
    let exe = std::env::current_exe().context("cannot locate own binary")?;
    let mount = Mount::Ro(exe, probe::SANDBOX_PATH.into());
    if !plan.mounts.contains(&mount) {
        plan.mounts.push(mount);
    }
    Ok(())
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
        broker: None,
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
