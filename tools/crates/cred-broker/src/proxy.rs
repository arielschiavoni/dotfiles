//! The proxy (`cred-broker serve`).
//!
//! A request from the sandbox goes through these steps:
//!   1. `CONNECT host:443` ([`Proxy::connect`]): the client asks for a
//!      tunnel. Its `Proxy-Authorization` username is the project org.
//!   2. A host without a rule is tunnelled as it is ([`tunnel`]): bytes are
//!      copied both ways, its TLS is never opened. A host with a rule is
//!      intercepted ([`Proxy::intercept`]): the broker answers the TLS with
//!      a certificate for the host from its CA, and reads the HTTP requests.
//!   3. Each request ([`Proxy::forward`]) is blocked, or gets the real
//!      credential of its rule, and is sent to the real host over a new TLS
//!      connection. The response streams back unchanged.
//!
//! Plain-HTTP requests (absolute URI) skip 1 and 2; they never get a token.
//! The broker's own endpoint, `http://cred-broker/health`, is one.

use std::convert::Infallible;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use http_body_util::combinators::BoxBody;
use http_body_util::{BodyExt, Empty, Full};
use hyper::body::{Bytes, Incoming};
use hyper::header::{self, HeaderMap, HeaderName, HeaderValue};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::upgrade::Upgraded;
use hyper::{Method, Request, Response, StatusCode, Uri};
use hyper_rustls::HttpsConnector;
use hyper_util::client::legacy::Client;
use hyper_util::client::legacy::connect::HttpConnector;
use hyper_util::rt::{TokioExecutor, TokioIo};
use serde::Serialize;
use serde_json::json;
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::TlsAcceptor;

use crate::ca::Ca;
use crate::config::{AuthScheme, Config, Route};
use crate::secrets::Secrets;

/// Request and response bodies: streamed from the other side, or our own.
type Body = BoxBody<Bytes, hyper::Error>;

/// Runs the proxy in the foreground until the process is killed.
pub async fn run(config: Config, config_path: PathBuf) -> Result<()> {
    use tokio::signal::unix::{SignalKind, signal};

    let port = config.port;
    let shown = config_path.display().to_string();
    let proxy = Proxy::new(config, config_path)?;
    let listener = TcpListener::bind(("127.0.0.1", port))
        .await
        .with_context(|| format!("cannot listen on 127.0.0.1:{port}"))?;
    let pid = std::process::id();
    note(&format!(
        "listening on 127.0.0.1:{port} (pid {pid}, config {shown})"
    ));

    // stopped by `cred-broker stop`/`kill` (SIGTERM) or Ctrl-C in `serve`
    let (mut term, mut int) = (
        signal(SignalKind::terminate())?,
        signal(SignalKind::interrupt())?,
    );
    let why = tokio::select! {
        () = serve(listener, Arc::new(proxy)) => "the listener ended",
        _ = term.recv() => "SIGTERM",
        _ = int.recv() => "SIGINT",
    };
    note(&format!("stopping (pid {pid}, {why})"));
    Ok(())
}

/// A line in broker.log (the process's stderr), with a timestamp.
pub fn note(message: &str) {
    let ts = jiff::Zoned::now().strftime("%Y-%m-%dT%H:%M:%S%z");
    eprintln!("{ts} {message}");
}

/// Accepts sandbox connections forever.
pub async fn serve(listener: TcpListener, proxy: Arc<Proxy>) {
    loop {
        let Ok((stream, _)) = listener.accept().await else {
            continue;
        };
        let proxy = proxy.clone();
        tokio::spawn(async move {
            let service = service_fn(move |req| proxy.clone().handle(req));
            // with_upgrades: after a CONNECT the connection becomes the tunnel.
            // An error here is the client going away: nothing to report.
            let _ = http1::Builder::new()
                .preserve_header_case(true)
                .title_case_headers(true)
                .serve_connection(TokioIo::new(stream), service)
                .with_upgrades()
                .await;
        });
    }
}

pub struct Proxy {
    config: Config,
    /// Shown by /health: which config this broker runs with.
    config_path: PathBuf,
    secrets: Secrets,
    ca: Ca,
    /// Connections to the real hosts, verified against the system CAs.
    client: Client<HttpsConnector<HttpConnector>, Body>,
    /// requests.jsonl
    log: PathBuf,
    started: u64,
}

/// Where the requests of a connection go.
struct Target {
    host: String,
    port: u16,
    /// Inside an intercepted tunnel. Only then are credentials added: never
    /// on a plaintext connection.
    tls: bool,
}

/// What a credential is, for the log and the cache.
#[derive(Default)]
struct Credential {
    /// The token used: the org, or `login`.
    key: Option<String>,
    /// Dropped from the cache on a 401.
    cache_key: Option<String>,
}

/// A line of requests.jsonl. No headers, bodies or query strings: they may
/// carry secrets.
#[derive(Serialize)]
struct Record<'a> {
    rule: &'a str,
    key: Option<&'a str>,
    method: &'a str,
    host: &'a str,
    path: &'a str,
    status: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl Proxy {
    pub fn new(config: Config, config_path: PathBuf) -> Result<Self> {
        let state = config.state_dir();
        std::fs::create_dir_all(&state)
            .with_context(|| format!("cannot create {}", state.display()))?;
        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_provider_and_native_roots(rustls::crypto::ring::default_provider())
            .context("cannot load the system CAs")?
            .https_or_http()
            .enable_http1()
            .build();
        Ok(Self {
            secrets: Secrets::new(config.auth()),
            ca: Ca::load_or_create(&state)?,
            client: Client::builder(TokioExecutor::new()).build(https),
            log: state.join("requests.jsonl"),
            started: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0, |d| d.as_secs()),
            config,
            config_path,
        })
    }

    /// A request on a sandbox connection: a CONNECT, or plain HTTP.
    async fn handle(self: Arc<Self>, req: Request<Incoming>) -> Result<Response<Body>, Infallible> {
        let hint = proxy_user(req.headers());
        if req.method() == Method::CONNECT {
            return Ok(self.connect(req, hint));
        }
        // plain HTTP through a proxy has the whole URL in the request line
        let Some(host) = req.uri().host().map(str::to_ascii_lowercase) else {
            return Ok(deny(
                StatusCode::BAD_REQUEST,
                "this is a proxy: absolute URL expected",
            ));
        };
        if host == crate::HOST {
            return Ok(self.own_endpoint(req.uri().path()));
        }
        let port = req.uri().port_u16().unwrap_or(80);
        let target = Target {
            host,
            port,
            tls: false,
        };
        Ok(self.forward(req, &target, hint.as_deref()).await)
    }

    /// Step 1: answers `200` to a CONNECT, then serves the tunnel in the
    /// background: decrypted if the host has a rule, else as it is.
    fn connect(self: Arc<Self>, req: Request<Incoming>, hint: Option<String>) -> Response<Body> {
        let Some(authority) = req.uri().authority() else {
            return deny(StatusCode::BAD_REQUEST, "CONNECT needs host:port");
        };
        let host = authority.host().to_ascii_lowercase();
        let port = authority.port_u16().unwrap_or(443);
        tokio::spawn(async move {
            // the client's connection, once hyper has sent the 200
            let Ok(upgraded) = hyper::upgrade::on(req).await else {
                return;
            };
            let client = TokioIo::new(upgraded);
            if self.config.intercepts(&host) {
                let target = Target {
                    host,
                    port,
                    tls: true,
                };
                if let Err(e) = self.intercept(client, target, hint).await {
                    // e.g. a client that does not trust the CA: worth a line
                    note(&format!("{e:#}"));
                }
            } else {
                // resets and timeouts are the client's business
                let _ = tunnel(client, &host, port).await;
            }
        });
        Response::new(Empty::new().map_err(|never| match never {}).boxed())
    }

    /// Step 2, a host with a rule: TLS as that host, then HTTP/1.1 requests.
    async fn intercept(
        self: Arc<Self>,
        client: TokioIo<Upgraded>,
        target: Target,
        hint: Option<String>,
    ) -> Result<()> {
        let config = self.ca.server_config(&target.host)?;
        let tls = TlsAcceptor::from(config)
            .accept(client)
            .await
            .with_context(|| format!("TLS with the sandbox for {}", target.host))?;
        let target = Arc::new(target);
        let service = service_fn(move |req| {
            let (proxy, target, hint) = (self.clone(), target.clone(), hint.clone());
            async move { Ok::<_, Infallible>(proxy.forward(req, &target, hint.as_deref()).await) }
        });
        // an error here is the client going away, as in `serve`
        let _ = http1::Builder::new()
            .preserve_header_case(true)
            .title_case_headers(true)
            .serve_connection(TokioIo::new(tls), service)
            .await;
        Ok(())
    }

    /// Step 3: blocks the request, or adds its rule's credential, and sends
    /// it to the real host. The response is streamed back as it arrives.
    async fn forward(
        &self,
        mut req: Request<Incoming>,
        t: &Target,
        hint: Option<&str>,
    ) -> Response<Body> {
        let path = req.uri().path().to_string();
        let method = req.method().to_string();
        let route = self.config.route(&t.host, &path);
        let log = |key: Option<&str>, status: Option<u16>, error: Option<String>| {
            if route != Route::Pass {
                let rule = route.name();
                let host = &t.host;
                self.log(&Record {
                    rule,
                    key,
                    method: &method,
                    host,
                    path: &path,
                    status,
                    error,
                });
            }
        };

        if let Route::Block(b) = route {
            log(None, Some(403), None);
            let why = format!("blocked by cred-broker ({}{})", t.host, b.path);
            return deny(StatusCode::FORBIDDEN, &why);
        }

        // the proxy's own headers; never forwarded
        req.headers_mut().remove(header::PROXY_AUTHORIZATION);
        req.headers_mut().remove("proxy-connection");

        let mut credential = Credential::default();
        if t.tls {
            match self.credential(&route, hint, req.headers_mut()).await {
                Ok(c) => credential = c,
                Err(e) => {
                    // no token: tell the client why, instead of a bare 401
                    let why = format!("cred-broker: {e:#}");
                    log(None, None, Some(why.clone()));
                    return deny(StatusCode::BAD_GATEWAY, &why);
                }
            }
            // inside the tunnel the request line has the path only
            let pq = req.uri().path_and_query().map_or("/", |pq| pq.as_str());
            match Uri::try_from(format!("https://{}:{}{pq}", t.host, t.port)) {
                Ok(uri) => *req.uri_mut() = uri,
                Err(_) => return deny(StatusCode::BAD_REQUEST, "invalid request path"),
            }
        }

        let key = credential.key.as_deref();
        match self.client.request(req.map(BodyExt::boxed)).await {
            Ok(resp) => {
                // 401: the token may have been rotated; read it again next time
                if resp.status() == StatusCode::UNAUTHORIZED
                    && let Some(cache_key) = &credential.cache_key
                {
                    self.secrets.forget(cache_key);
                }
                log(key, Some(resp.status().as_u16()), None);
                resp.map(BodyExt::boxed)
            }
            Err(e) => {
                let why = format!("cred-broker: {}: {e}", t.host);
                log(key, None, Some(why.clone()));
                deny(StatusCode::BAD_GATEWAY, &why)
            }
        }
    }

    /// Puts the real credential of `route` into `headers`, replacing whatever
    /// the sandbox sent (a placeholder, or nothing).
    async fn credential(
        &self,
        route: &Route<'_>,
        hint: Option<&str>,
        headers: &mut HeaderMap,
    ) -> Result<Credential> {
        match *route {
            // pi's login (model requests)
            Route::Login(p) => {
                let (token, refreshed) = self
                    .secrets
                    .login_token(p, &self.config.oauth.token_command)
                    .await?;
                if refreshed {
                    self.log(&json!({"event": "refresh", "provider": p.name()}));
                }
                headers.remove("x-api-key");
                set_secret(headers, header::AUTHORIZATION, &format!("Bearer {token}"))?;
                Ok(Credential::default())
            }
            // Copilot's plan and quotas: the account of pi's Copilot login,
            // not the project's GitHub token (which may be another account)
            Route::CopilotInfo => {
                let token = self.secrets.copilot_github_token()?;
                set_secret(headers, header::AUTHORIZATION, &format!("Bearer {token}"))?;
                Ok(Credential {
                    key: Some("login".into()),
                    cache_key: None,
                })
            }
            // the project org's token (the proxy username), else `default`
            Route::GitHub(scheme) => {
                let org = hint.unwrap_or("default");
                let token = self
                    .secrets
                    .github_token(org, &self.config.github.token_command)
                    .await?;
                let value = match scheme {
                    AuthScheme::Bearer => format!("Bearer {token}"),
                    AuthScheme::Basic => {
                        format!("Basic {}", BASE64.encode(format!("x-access-token:{token}")))
                    }
                };
                set_secret(headers, header::AUTHORIZATION, &value)?;
                Ok(Credential {
                    key: Some(org.into()),
                    cache_key: Some(Secrets::github_key(org)),
                })
            }
            // static headers (Jira)
            Route::Header(h) => {
                let secret = self.secrets.header_secret(h).await?;
                let name = HeaderName::try_from(h.header.as_str())
                    .with_context(|| format!("rule '{}': invalid header name", h.name))?;
                set_secret(headers, name, &h.value.replace("{secret}", &secret))?;
                Ok(Credential {
                    key: None,
                    cache_key: Some(Secrets::header_key(h)),
                })
            }
            Route::Block(_) | Route::Pass => Ok(Credential::default()),
        }
    }

    /// `http://cred-broker/health`: whether a broker runs, and which pid
    /// `stop` kills.
    fn own_endpoint(&self, path: &str) -> Response<Body> {
        if path != "/health" {
            return deny(StatusCode::NOT_FOUND, "unknown cred-broker endpoint");
        }
        let body = json!({
            "pid": std::process::id(),
            "started": self.started,
            "config": self.config_path,
        });
        json_response(StatusCode::OK, &body)
    }

    /// Appends a line to requests.jsonl.
    fn log(&self, record: &impl Serialize) {
        let ts = jiff::Zoned::now()
            .strftime("%Y-%m-%dT%H:%M:%S%z")
            .to_string();
        let mut line = json!({ "ts": ts });
        if let (Some(line), serde_json::Value::Object(fields)) = (
            line.as_object_mut(),
            serde_json::to_value(record).unwrap_or_default(),
        ) {
            line.extend(fields);
        }
        let file = OpenOptions::new().create(true).append(true).open(&self.log);
        if let Ok(mut f) = file {
            let _ = writeln!(f, "{line}");
        }
    }
}

/// Step 2, a host without a rule: copies bytes both ways, TLS untouched.
async fn tunnel(mut client: TokioIo<Upgraded>, host: &str, port: u16) -> std::io::Result<()> {
    let mut server = TcpStream::connect((host, port)).await?;
    tokio::io::copy_bidirectional(&mut client, &mut server).await?;
    Ok(())
}

/// Username of `Proxy-Authorization: Basic ...`. pi-safe puts the project org
/// there (HTTPS_PROXY=http://<org>:pi-safe@...): a hint, not a credential.
/// pi-safe only uses characters that need no URL escaping.
fn proxy_user(headers: &HeaderMap) -> Option<String> {
    let value = headers.get(header::PROXY_AUTHORIZATION)?.to_str().ok()?;
    let (scheme, encoded) = value.split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("basic") {
        return None;
    }
    let decoded = String::from_utf8(BASE64.decode(encoded.trim()).ok()?).ok()?;
    let user = decoded.split(':').next()?;
    (!user.is_empty()).then(|| user.to_string())
}

/// Sets a header whose value is a secret: marked sensitive, so hyper never
/// puts it into debug output.
fn set_secret(headers: &mut HeaderMap, name: HeaderName, value: &str) -> Result<()> {
    let mut value =
        HeaderValue::try_from(value).context("the secret is not a valid header value")?;
    value.set_sensitive(true);
    headers.insert(name, value);
    Ok(())
}

/// An error answer of the broker itself: `{"message": ...}`.
fn deny(status: StatusCode, message: &str) -> Response<Body> {
    json_response(status, &json!({ "message": message }))
}

fn json_response(status: StatusCode, body: &serde_json::Value) -> Response<Body> {
    let mut resp = Response::new(
        Full::new(Bytes::from(body.to_string()))
            .map_err(|never| match never {})
            .boxed(),
    );
    *resp.status_mut() = status;
    resp.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/json"),
    );
    resp
}

#[cfg(test)]
mod tests {
    use super::*;
    use rustls::pki_types::pem::PemObject;
    use rustls::pki_types::{CertificateDer, ServerName};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    /// A broker on a free port, with rules that need no network or secrets.
    async fn start() -> (u16, PathBuf) {
        let dir = crate::test_dir("proxy");
        let config: Config = toml::from_str(&format!(
            "state_dir = '{}'\n[[block]]\nhost = 'blocked.test'\npath = '/secret'\n",
            dir.display()
        ))
        .unwrap();
        let proxy = Proxy::new(config, dir.join("config.toml")).unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        tokio::spawn(serve(listener, Arc::new(proxy)));
        (port, dir)
    }

    async fn read_all(mut s: impl AsyncReadExt + Unpin) -> String {
        let mut out = Vec::new();
        let _ = s.read_to_end(&mut out).await;
        String::from_utf8_lossy(&out).into_owned()
    }

    #[tokio::test]
    async fn health_over_plain_http() {
        let (port, dir) = start().await;
        let mut s = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        s.write_all(b"GET http://cred-broker/health HTTP/1.1\r\nHost: cred-broker\r\nConnection: close\r\n\r\n")
            .await
            .unwrap();
        let resp = read_all(s).await;
        assert!(resp.starts_with("HTTP/1.1 200"), "{resp}");
        assert!(
            resp.contains(&format!("\"pid\":{}", std::process::id())),
            "{resp}"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// CONNECT, TLS with a certificate from the broker's CA, then a request
    /// the broker answers itself: interception works end to end.
    #[tokio::test]
    async fn intercepts_tls_and_blocks() {
        let (port, dir) = start().await;
        let mut s = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        s.write_all(b"CONNECT blocked.test:443 HTTP/1.1\r\nHost: blocked.test:443\r\n\r\n")
            .await
            .unwrap();
        // the 200 (with a Date header), up to the blank line
        let mut head = Vec::new();
        while !head.ends_with(b"\r\n\r\n") {
            head.push(s.read_u8().await.unwrap());
        }
        assert!(head.starts_with(b"HTTP/1.1 200 OK\r\n"));

        let mut roots = rustls::RootCertStore::empty();
        roots
            .add(CertificateDer::from_pem_file(Ca::cert_path(&dir)).unwrap())
            .unwrap();
        let config = rustls::ClientConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
        let name = ServerName::try_from("blocked.test").unwrap();
        let mut tls = tokio_rustls::TlsConnector::from(Arc::new(config))
            .connect(name, s)
            .await
            .expect("the broker's certificate is trusted");
        tls.write_all(b"GET /secret/x HTTP/1.1\r\nHost: blocked.test\r\nConnection: close\r\n\r\n")
            .await
            .unwrap();
        let resp = read_all(tls).await;
        assert!(resp.starts_with("HTTP/1.1 403"), "{resp}");
        assert!(resp.contains("blocked by cred-broker (blocked.test/secret)"));

        let log = std::fs::read_to_string(dir.join("requests.jsonl")).unwrap();
        assert!(
            log.contains(r#""rule":"block""#) && log.contains(r#""status":403"#),
            "{log}"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn proxy_user_is_the_basic_username() {
        let mut h = HeaderMap::new();
        let basic = format!("Basic {}", BASE64.encode("ASG-SONG:pi-safe"));
        h.insert(header::PROXY_AUTHORIZATION, basic.parse().unwrap());
        assert_eq!(proxy_user(&h).as_deref(), Some("ASG-SONG"));
        h.insert(header::PROXY_AUTHORIZATION, "Bearer x".parse().unwrap());
        assert_eq!(proxy_user(&h), None);
        assert_eq!(proxy_user(&HeaderMap::new()), None);
    }
}
