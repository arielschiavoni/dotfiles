//! cred-broker: an HTTP proxy on 127.0.0.1 that puts the real credentials
//! into the requests of sandboxed agents, which only hold placeholders.
//!
//! Only hosts with a rule in config.toml are decrypted (with a certificate
//! from its own CA, which the sandbox trusts); all other traffic is tunnelled
//! untouched. The tokens live only in this process. pi-safe is its client:
//! it runs `cred-broker start` and `status --json`.
//!
//! Modules, in the order a request meets them:
//!   proxy    connections: CONNECT, tunnel or intercept, forward
//!   config   config.toml, and which rule a request falls under
//!   secrets  where the credentials come from (gopass, pi, env)
//!   aws      AWS credentials handed to the sandbox (`/aws/<profile>`)
//!   ca       the CA and its per-host certificates
//!   daemon   start / stop / status of the background process

mod aws;
mod ca;
mod config;
mod daemon;
mod proxy;
mod secrets;

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

use config::Config;
use daemon::Daemon;

/// Host of the broker's own endpoints, `http://cred-broker/health` and
/// `/aws/<profile>`: answered by the proxy itself, never forwarded.
pub const HOST: &str = "cred-broker";

/// Proxy that puts real credentials into the requests of sandboxed agents.
#[derive(Parser)]
#[command(
    name = "cred-broker",
    after_help = "Config: ~/.config/cred-broker/config.toml"
)]
struct Cli {
    /// Config file [default: ~/.config/cred-broker/config.toml]
    #[arg(long, global = true, value_name = "FILE")]
    config: Option<PathBuf>,
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Start it in the background, unless it is running
    Start,
    /// Stop it (its tokens are dropped from memory)
    Stop,
    /// Stop and start: re-reads the config, the tokens and the binary
    Restart,
    /// Whether it runs, and where its files are (exit 1: not running)
    Status {
        /// As JSON, for clients (pi-safe); always exits 0
        #[arg(long)]
        json: bool,
    },
    /// Run the proxy in the foreground (what `start` runs detached)
    Serve,
}

fn main() -> ExitCode {
    match run(Cli::parse()) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("cred-broker: {e:#}");
            ExitCode::from(2)
        }
    }
}

fn run(cli: Cli) -> Result<ExitCode> {
    let path = cli.config.unwrap_or_else(Config::default_path);
    // loaded by every command: a broken config fails here, in the terminal,
    // not in the detached process's log
    let config = Config::load(&path)?;
    let daemon = Daemon::new(&config, &path);
    let running = |pid: u32| {
        println!(
            "cred-broker running (pid {pid}) on 127.0.0.1:{}",
            config.port
        )
    };

    match cli.command {
        Cmd::Start => running(daemon.start()?),
        Cmd::Stop => match daemon.stop()? {
            true => println!("cred-broker stopped"),
            false => println!("cred-broker was not running"),
        },
        Cmd::Restart => {
            daemon.stop()?;
            running(daemon.start()?);
        }
        Cmd::Status { json: true } => {
            println!("{}", serde_json::to_string_pretty(&daemon.status())?);
        }
        Cmd::Status { json: false } => {
            let s = daemon.status();
            match s.pid {
                Some(pid) => running(pid),
                None => println!("cred-broker not running (port {})", s.port),
            }
            println!("config    {}", path.display());
            println!("requests  {}", s.requests.display());
            println!("log       {}", s.log.display());
            println!("ca        {}", s.ca.display());
            if !s.running {
                return Ok(ExitCode::FAILURE);
            }
        }
        Cmd::Serve => {
            let runtime = tokio::runtime::Runtime::new().context("tokio runtime")?;
            // into broker.log like its other lines, with a timestamp
            if let Err(e) = runtime.block_on(proxy::run(config, path)) {
                proxy::note(&format!("cannot serve: {e:#}"));
                return Ok(ExitCode::FAILURE);
            }
        }
    }
    Ok(ExitCode::SUCCESS)
}

/// A fresh, empty directory for a test.
#[cfg(test)]
pub fn test_dir(name: &str) -> PathBuf {
    use std::sync::atomic::{AtomicU32, Ordering};
    static N: AtomicU32 = AtomicU32::new(0);
    let n = N.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("cred-broker-{name}-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}
