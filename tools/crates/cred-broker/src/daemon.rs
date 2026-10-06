//! Running the proxy in the background: `start`, `stop`, `status`.
//!
//! There is no pid file: the running broker is whatever answers
//! `http://cred-broker/health` on the port, and that answer has its pid.

use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use serde::Serialize;
use serde_json::Value;

use crate::ca::Ca;
use crate::config::Config;

const START_TIMEOUT: Duration = Duration::from_secs(20);
const STOP_TIMEOUT: Duration = Duration::from_secs(10);

pub struct Daemon {
    port: u16,
    state_dir: PathBuf,
    /// Passed on to `serve`.
    config_path: PathBuf,
}

/// `cred-broker status --json`: what a client (pi-safe) needs to use it.
#[derive(Serialize)]
pub struct Status {
    pub running: bool,
    pub pid: Option<u32>,
    /// Proxy at 127.0.0.1:port.
    pub port: u16,
    /// The broker's own endpoint, through the proxy.
    pub health: String,
    /// The CA certificate clients must trust (created on first start).
    pub ca: PathBuf,
    /// One line per brokered request.
    pub requests: PathBuf,
    /// The proxy's stderr: startup errors, TLS failures.
    pub log: PathBuf,
}

impl Daemon {
    pub fn new(config: &Config, config_path: &Path) -> Self {
        Self {
            port: config.port,
            state_dir: config.state_dir(),
            config_path: config_path.to_path_buf(),
        }
    }

    fn addr(&self) -> SocketAddr {
        SocketAddr::from(([127, 0, 0, 1], self.port))
    }

    fn log(&self) -> PathBuf {
        self.state_dir.join("broker.log")
    }

    pub fn status(&self) -> Status {
        let pid = self.pid();
        Status {
            running: pid.is_some(),
            pid,
            port: self.port,
            health: format!("http://{}/health", crate::HOST),
            ca: Ca::cert_path(&self.state_dir),
            requests: self.state_dir.join("requests.jsonl"),
            log: self.log(),
        }
    }

    /// Pid of the broker answering on the port, if one does.
    pub fn pid(&self) -> Option<u32> {
        let v: Value = serde_json::from_str(&self.get_health().ok()?).ok()?;
        v.get("pid")?.as_u64().map(|p| p as u32)
    }

    /// `GET http://cred-broker/health` through the proxy, over plain TCP.
    fn get_health(&self) -> Result<String> {
        let mut s = TcpStream::connect_timeout(&self.addr(), Duration::from_millis(500))?;
        s.set_read_timeout(Some(Duration::from_secs(3)))?;
        let host = crate::HOST;
        write!(
            s,
            "GET http://{host}/health HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n"
        )?;
        let mut resp = String::new();
        s.read_to_string(&mut resp)?;
        let (head, body) = resp.split_once("\r\n\r\n").context("bad response")?;
        if !head.starts_with("HTTP/1.1 200") {
            bail!("{}", head.lines().next().unwrap_or_default());
        }
        Ok(body.to_string())
    }

    /// Starts the broker in the background unless one is running; waits
    /// until it answers. Returns its pid.
    pub fn start(&self) -> Result<u32> {
        if let Some(pid) = self.pid() {
            return Ok(pid);
        }
        if TcpStream::connect_timeout(&self.addr(), Duration::from_millis(300)).is_ok() {
            bail!(
                "port {} is in use by something that is not cred-broker",
                self.port
            );
        }
        fs::create_dir_all(&self.state_dir)?;
        let log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.log())?;
        let exe = std::env::current_exe().context("cannot find cred-broker's own binary")?;
        let config = self
            .config_path
            .canonicalize()
            .unwrap_or_else(|_| self.config_path.clone());
        let status = Command::new("setsid")
            .arg("-f") // own session, in the background: outlives the terminal
            .arg(exe)
            .arg("--config")
            .arg(config)
            .arg("serve")
            .stdin(Stdio::null())
            .stdout(log.try_clone()?)
            .stderr(log)
            .status()
            .context("cannot run setsid")?;
        if !status.success() {
            bail!("cannot start cred-broker");
        }
        let deadline = Instant::now() + START_TIMEOUT;
        while Instant::now() < deadline {
            if let Some(pid) = self.pid() {
                return Ok(pid);
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        bail!(
            "cred-broker did not come up within {}s - see {}",
            START_TIMEOUT.as_secs(),
            self.log().display()
        )
    }

    /// Stops the running broker; false if none was running.
    pub fn stop(&self) -> Result<bool> {
        let Some(pid) = self.pid() else {
            return Ok(false);
        };
        if !Command::new("kill")
            .arg(pid.to_string())
            .status()?
            .success()
        {
            bail!("cannot stop cred-broker (pid {pid})");
        }
        // gone once the port is free, not when /health stops answering: the
        // exiting process still holds it for a moment, and `restart` needs it
        let deadline = Instant::now() + STOP_TIMEOUT;
        while TcpStream::connect_timeout(&self.addr(), Duration::from_millis(200)).is_ok() {
            if Instant::now() > deadline {
                bail!("cred-broker (pid {pid}) did not stop");
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        Ok(true)
    }
}
