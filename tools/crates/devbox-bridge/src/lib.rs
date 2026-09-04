//! Shared core for the devbox guest-to-host bridge: a daemon for the Mac plus
//! the guest commands that forward to it over the SSH reverse tunnel.
//!
//! - `xdg-open` — open a URL in the Mac browser
//! - `xclip` — read the Mac clipboard as PNG
//!
//! Both halves link this library, so validation and framing are defined once.
//!
//! Wire format — one request per connection, newline-framed:
//!
//! ```text
//! -> OPEN https://example.com    <- OK
//! -> CLIP-TYPES                  <- OK-TEXT image/png     (or OK-NONE)
//! -> CLIP-IMAGE                  <- OK-BYTES 40213
//!                                   <40213 bytes of PNG>  (or OK-NONE)
//! -> anything                    <- ERR <reason>
//! ```
//!
//! Only `OK-BYTES` carries a body. Its length is declared up front, so the
//! reader never looks for a delimiter inside binary data.

use std::fmt;
use std::io::{self, BufRead, BufReader, Read, Write};

/// Loopback port. Also in `devbox/scripts/ssh-config.sh` as the
/// `RemoteForward` endpoint; change both together.
pub const PORT: u16 = 17325;

/// Loopback only — the guest arrives via the SSH reverse tunnel.
pub const HOST: &str = "127.0.0.1";

/// Longest URL accepted. 8 KiB because SAML redirects run to several
/// kilobytes, and a refused login looks like a broken tool.
pub const MAX_LEN: usize = 8192;

/// Longest line either side reads. A response is `"ERR "` plus a [`Rejection`]
/// message, so it needs headroom over [`MAX_LEN`].
pub const MAX_LINE: usize = MAX_LEN + 256;

/// Largest clipboard image accepted, checked before allocating.
pub const MAX_IMAGE: usize = 32 * 1024 * 1024;

/// Message for a tunnel with nothing behind it. Shared by both guest commands
/// so the two cannot drift.
pub fn tunnel_down(addr: &str) -> String {
    format!(
        "nothing is listening on {addr}.\n\
         The reverse tunnel only exists inside an `ssh devbox` session \
         (`limactl shell devbox` never has it).\n\
         Check the Mac end with: devbox-bridge --status"
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Validation
// ─────────────────────────────────────────────────────────────────────────────

/// Why a URL was refused. Carries the offending byte and offset so the message
/// stays actionable when it surfaces inside lazygit months from now.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Rejection {
    /// Missing, or entirely whitespace.
    Empty,
    /// Longer than [`MAX_LEN`].
    TooLong { len: usize },
    /// Not `http://` or `https://`.
    NotHttp,
    /// Nothing between `://` and the first `/`, `?` or `#`.
    NoHost,
    /// Byte >= 0x80 — not pure ASCII.
    NonAscii { byte: u8, at: usize },
    /// Control byte or raw space. `\n` would also break the wire framing.
    Forbidden { byte: u8, at: usize },
}

impl fmt::Display for Rejection {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Rejection::Empty => write!(f, "empty URL"),
            Rejection::TooLong { len } => {
                write!(f, "URL is {len} bytes, limit is {MAX_LEN}")
            }
            Rejection::NotHttp => write!(
                f,
                "must start with http:// or https:// (refusing to hand anything \
                 else to `open`)"
            ),
            Rejection::NoHost => write!(f, "no host between the scheme and the path"),
            Rejection::NonAscii { byte, at } => write!(
                f,
                "non-ASCII byte 0x{byte:02x} at offset {at}: internationalised \
                 hosts and unicode paths are not supported, percent-encode the \
                 URL first"
            ),
            Rejection::Forbidden { byte, at } => match byte {
                b' ' => write!(f, "space at offset {at}: percent-encode it as %20"),
                b'\n' => write!(f, "newline at offset {at}"),
                _ => write!(f, "forbidden control byte 0x{byte:02x} at offset {at}"),
            },
        }
    }
}

impl std::error::Error for Rejection {}

/// Validate a URL and return the form to put on the wire.
///
/// The `http(s)://` prefix check limits schemes, and stops `open` reading the
/// string as a flag (leading `-`) or as a local file (bare path). The byte
/// range rejects non-ASCII and `\n`, which would break the framing.
///
/// Returns an owned `String` so swapping in the `url` crate (see `Cargo.toml`)
/// would touch this body and no call sites.
pub fn normalize(input: &str) -> Result<String, Rejection> {
    let url = input.trim();

    if url.is_empty() {
        return Err(Rejection::Empty);
    }
    if url.len() > MAX_LEN {
        return Err(Rejection::TooLong { len: url.len() });
    }

    let rest = match strip_scheme(url) {
        Some(rest) => rest,
        None => return Err(Rejection::NotHttp),
    };

    // Bytes, not chars: `at` has to be a byte offset to be useful in the error.
    for (at, byte) in url.bytes().enumerate() {
        match byte {
            0x21..=0x7e => {}
            0x80.. => return Err(Rejection::NonAscii { byte, at }),
            _ => return Err(Rejection::Forbidden { byte, at }),
        }
    }

    // Authority ends at the first `/`, `?` or `#`; anything before `@` is
    // userinfo, so `https://user@` has no host.
    let authority = rest.find(['/', '?', '#']).map_or(rest, |end| &rest[..end]);
    let host = authority.rsplit('@').next().unwrap_or("");
    if host.is_empty() {
        return Err(Rejection::NoHost);
    }

    Ok(url.to_owned())
}

/// Everything after `http://` or `https://`, or `None` for any other scheme.
/// Case-insensitive: `HTTPS://` is valid.
fn strip_scheme(url: &str) -> Option<&str> {
    for prefix in ["http://", "https://"] {
        if url.len() >= prefix.len() && url[..prefix.len()].eq_ignore_ascii_case(prefix) {
            return Some(&url[prefix.len()..]);
        }
    }
    None
}

// ─────────────────────────────────────────────────────────────────────────────
// Requests
// ─────────────────────────────────────────────────────────────────────────────

/// What a guest command is asking the Mac to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Request {
    /// Open this URL in the Mac browser. Validated by the daemon, which is the
    /// side that launches something.
    Open(String),
    /// Which clipboard formats can be served? What `xclip -t TARGETS -o` asks.
    ClipTypes,
    /// Send the clipboard as PNG.
    ClipImage,
}

impl Request {
    /// Render as a single framed line, newline included.
    pub fn encode(&self) -> String {
        match self {
            Request::Open(url) => format!("OPEN {url}\n"),
            Request::ClipTypes => "CLIP-TYPES\n".to_owned(),
            Request::ClipImage => "CLIP-IMAGE\n".to_owned(),
        }
    }

    /// Parse a line from [`Request::encode`], newline already stripped.
    pub fn parse(line: &str) -> Result<Request, String> {
        let line = line.trim();

        if let Some(url) = line.strip_prefix("OPEN ") {
            return Ok(Request::Open(url.trim().to_owned()));
        }
        match line {
            "CLIP-TYPES" => Ok(Request::ClipTypes),
            "CLIP-IMAGE" => Ok(Request::ClipImage),
            _ => Err(format!("unknown request {line:?}")),
        }
    }

    /// Write the request line to a socket.
    pub fn write_to<W: Write>(&self, mut writer: W) -> io::Result<()> {
        writer.write_all(self.encode().as_bytes())?;
        writer.flush()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Responses
// ─────────────────────────────────────────────────────────────────────────────

/// The daemon's answer to a request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Response {
    /// Done. Only `OPEN` uses this.
    Ok,
    /// The clipboard holds no image. Distinct from an empty `Bytes` so
    /// "nothing there" and "here it is" cannot be confused.
    Empty,
    /// A short one-line answer, such as `image/png`.
    Text(String),
    /// Binary payload, length-declared on the wire.
    Bytes(Vec<u8>),
    /// Refused, or failed. The string is already human-readable.
    Err(String),
}

impl Response {
    /// Write the header line and, for [`Response::Bytes`], the body after it.
    pub fn write_to<W: Write>(&self, mut writer: W) -> io::Result<()> {
        match self {
            Response::Ok => writer.write_all(b"OK\n")?,
            Response::Empty => writer.write_all(b"OK-NONE\n")?,
            // A newline in the payload would desynchronise the framing.
            Response::Text(text) => {
                writer.write_all(format!("OK-TEXT {}\n", flatten(text)).as_bytes())?
            }
            Response::Bytes(body) => {
                writer.write_all(format!("OK-BYTES {}\n", body.len()).as_bytes())?;
                writer.write_all(body)?;
            }
            Response::Err(reason) => {
                writer.write_all(format!("ERR {}\n", flatten(reason)).as_bytes())?
            }
        }
        writer.flush()
    }

    /// Read one response, body included.
    ///
    /// `Ok(None)` means the peer closed without answering. Callers report that
    /// rather than assume success: there is no way to tell whether the request
    /// took effect.
    pub fn read_from<R: Read>(reader: R) -> io::Result<Option<Response>> {
        let mut reader = BufReader::new(reader);

        let Some(line) = read_line(&mut reader, MAX_LINE)? else {
            return Ok(None);
        };

        if line == "OK" {
            return Ok(Some(Response::Ok));
        }
        if line == "OK-NONE" {
            return Ok(Some(Response::Empty));
        }
        if let Some(text) = line.strip_prefix("OK-TEXT ") {
            return Ok(Some(Response::Text(text.to_owned())));
        }
        if let Some(reason) = line.strip_prefix("ERR ") {
            return Ok(Some(Response::Err(reason.to_owned())));
        }
        if let Some(len) = line.strip_prefix("OK-BYTES ") {
            let len: usize = len
                .trim()
                .parse()
                .map_err(|_| invalid(format!("OK-BYTES length is not a number: {len:?}")))?;
            // Checked before allocating, not after reading.
            if len > MAX_IMAGE {
                return Err(invalid(format!(
                    "peer offered {len} bytes, limit is {MAX_IMAGE}"
                )));
            }
            let mut body = vec![0u8; len];
            reader.read_exact(&mut body)?;
            return Ok(Some(Response::Bytes(body)));
        }

        // An unrecognised line becomes an error rather than a silent success.
        Ok(Some(Response::Err(format!(
            "unrecognised response from daemon: {line:?}"
        ))))
    }
}

fn flatten(s: &str) -> String {
    s.replace('\n', " ")
}

fn invalid(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, msg)
}

// ─────────────────────────────────────────────────────────────────────────────
// Framing
// ─────────────────────────────────────────────────────────────────────────────

/// Read one line for a request, which never carries a body.
///
/// `Ok(None)` means the peer closed without sending anything — the liveness
/// probe `devbox-bridge --status` makes, so it must not be an error. `Err` is
/// a partial or overlong line, since a truncated URL must never pass as a
/// short one.
pub fn read_framed_line<R: Read>(reader: R) -> io::Result<Option<String>> {
    read_line(&mut BufReader::new(reader), MAX_LINE)
}

/// Takes `&mut` and uses `by_ref` so the caller keeps the buffered reader:
/// `Response::read_from` needs it for the body already pulled in behind the
/// newline.
fn read_line<R: BufRead>(reader: &mut R, max: usize) -> io::Result<Option<String>> {
    let mut buf = Vec::new();
    reader
        .by_ref()
        .take(max as u64 + 1)
        .read_until(b'\n', &mut buf)?;

    if buf.is_empty() {
        return Ok(None);
    }

    if buf.last() != Some(&b'\n') {
        return Err(invalid(format!(
            "no newline within {max} bytes after {} bytes \
             (peer closed mid-line, or line too long)",
            buf.len()
        )));
    }
    buf.pop();

    String::from_utf8(buf)
        .map(Some)
        .map_err(|e| invalid(e.to_string()))
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── normalize: accepted ──────────────────────────────────────────────────

    #[test]
    fn accepts_plain_https() {
        assert_eq!(
            normalize("https://example.com").unwrap(),
            "https://example.com"
        );
    }

    #[test]
    fn accepts_http() {
        assert_eq!(
            normalize("http://example.com").unwrap(),
            "http://example.com"
        );
    }

    #[test]
    fn accepts_uppercase_scheme() {
        assert_eq!(
            normalize("HTTPS://example.com").unwrap(),
            "HTTPS://example.com"
        );
    }

    #[test]
    fn accepts_github_pull_request() {
        let url = "https://github.com/owner/repo/pull/42";
        assert_eq!(normalize(url).unwrap(), url);
    }

    /// `&` and `#` are what a shell-based implementation would mangle.
    #[test]
    fn preserves_query_and_fragment() {
        let url = "https://example.com/a/b?x=1&y=2#frag";
        assert_eq!(normalize(url).unwrap(), url);
    }

    #[test]
    fn accepts_port_and_userinfo() {
        let url = "http://user@example.com:8080/path";
        assert_eq!(normalize(url).unwrap(), url);
    }

    #[test]
    fn trims_surrounding_whitespace() {
        assert_eq!(
            normalize("  https://example.com\n").unwrap(),
            "https://example.com"
        );
    }

    // ── normalize: rejected ──────────────────────────────────────────────────

    #[test]
    fn rejects_empty() {
        assert_eq!(normalize("").unwrap_err(), Rejection::Empty);
        assert_eq!(normalize("   ").unwrap_err(), Rejection::Empty);
    }

    /// `open` would treat this as a local file path.
    #[test]
    fn rejects_file_scheme() {
        assert_eq!(
            normalize("file:///etc/passwd").unwrap_err(),
            Rejection::NotHttp
        );
    }

    /// `open` would read this as a flag.
    #[test]
    fn rejects_leading_dash() {
        assert_eq!(normalize("-a Calculator").unwrap_err(), Rejection::NotHttp);
    }

    #[test]
    fn rejects_other_schemes() {
        for url in ["javascript:alert(1)", "ftp://x.com", "x-man-page://ls"] {
            assert_eq!(normalize(url).unwrap_err(), Rejection::NotHttp, "{url}");
        }
    }

    #[test]
    fn rejects_bare_path() {
        assert_eq!(normalize("/etc/passwd").unwrap_err(), Rejection::NotHttp);
    }

    #[test]
    fn rejects_missing_host() {
        assert_eq!(normalize("https://").unwrap_err(), Rejection::NoHost);
        assert_eq!(normalize("https:///path").unwrap_err(), Rejection::NoHost);
        assert_eq!(normalize("https://user@").unwrap_err(), Rejection::NoHost);
    }

    /// Framing safety: no smuggling a second request past the daemon.
    #[test]
    fn rejects_embedded_newline() {
        let err = normalize("https://example.com\nhttps://evil.example").unwrap_err();
        assert_eq!(
            err,
            Rejection::Forbidden {
                byte: b'\n',
                at: 19
            }
        );
    }

    #[test]
    fn rejects_raw_space_with_actionable_message() {
        let err = normalize("https://example.com/my report.pdf").unwrap_err();
        assert_eq!(err, Rejection::Forbidden { byte: b' ', at: 22 });
        assert!(err.to_string().contains("%20"), "{err}");
    }

    #[test]
    fn rejects_too_long() {
        let url = format!("https://example.com/{}", "a".repeat(MAX_LEN));
        assert!(matches!(
            normalize(&url).unwrap_err(),
            Rejection::TooLong { .. }
        ));
    }

    /// Pins the ASCII-only limitation. Adopting the `url` crate flips this to
    /// "percent-encoded".
    #[test]
    fn rejects_non_ascii_path_for_now() {
        let err = normalize("https://de.wikipedia.org/wiki/Bahnhofstraße").unwrap_err();
        assert!(
            matches!(err, Rejection::NonAscii { .. }),
            "expected NonAscii, got {err:?}"
        );
        // The message has to tell the reader what to do about it.
        assert!(err.to_string().contains("percent-encode"), "{err}");
    }

    /// An internationalised host would need Punycode.
    #[test]
    fn rejects_idn_host_for_now() {
        let err = normalize("https://bücher.example/x").unwrap_err();
        assert!(matches!(err, Rejection::NonAscii { .. }), "{err:?}");
    }

    // ── requests ─────────────────────────────────────────────────────────────

    #[test]
    fn request_round_trips() {
        for original in [
            Request::Open("https://example.com/a?b=1&c=2#d".to_owned()),
            Request::ClipTypes,
            Request::ClipImage,
        ] {
            let encoded = original.encode();
            assert!(encoded.ends_with('\n'));
            let line = encoded.trim_end_matches('\n');
            assert_eq!(Request::parse(line).unwrap(), original);
        }
    }

    #[test]
    fn request_is_newline_framed() {
        let mut out = Vec::new();
        Request::ClipImage.write_to(&mut out).unwrap();
        assert_eq!(out, b"CLIP-IMAGE\n");
    }

    #[test]
    fn unknown_request_is_rejected() {
        for line in ["CLIP-VIDEO", "https://example.com", "/etc/passwd", ""] {
            assert!(Request::parse(line).is_err(), "{line}");
        }
    }

    // ── responses ────────────────────────────────────────────────────────────

    #[test]
    fn response_round_trips() {
        for original in [
            Response::Ok,
            Response::Empty,
            Response::Text("image/png".to_owned()),
            Response::Bytes(vec![0x89, b'P', b'N', b'G', 0x00, 0xff]),
            Response::Err("must start with http:// or https://".to_owned()),
        ] {
            let mut wire = Vec::new();
            original.write_to(&mut wire).unwrap();
            assert_eq!(Response::read_from(&wire[..]).unwrap(), Some(original));
        }
    }

    /// The point of the length prefix: newlines and NULs arrive intact.
    #[test]
    fn binary_body_survives_newlines_and_nuls() {
        let body: Vec<u8> = (0..=255u8).chain(b"\n\n\n".iter().copied()).collect();
        let mut wire = Vec::new();
        Response::Bytes(body.clone()).write_to(&mut wire).unwrap();
        assert_eq!(
            Response::read_from(&wire[..]).unwrap(),
            Some(Response::Bytes(body))
        );
    }

    #[test]
    fn empty_body_is_valid() {
        let mut wire = Vec::new();
        Response::Bytes(Vec::new()).write_to(&mut wire).unwrap();
        assert_eq!(wire, b"OK-BYTES 0\n");
    }

    #[test]
    fn response_flattens_newlines_in_reason() {
        let mut wire = Vec::new();
        Response::Err("two\nlines".to_owned())
            .write_to(&mut wire)
            .unwrap();
        assert_eq!(wire, b"ERR two lines\n");
    }

    #[test]
    fn unrecognised_response_is_an_error_not_a_success() {
        assert!(matches!(
            Response::read_from(&b"banana\n"[..]).unwrap(),
            Some(Response::Err(_))
        ));
    }

    /// An absurd declared length must not make the guest reserve gigabytes.
    #[test]
    fn oversized_body_is_refused_without_allocating() {
        let header = format!("OK-BYTES {}\n", MAX_IMAGE + 1);
        let err = Response::read_from(header.as_bytes()).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
        assert!(err.to_string().contains("limit is"), "{err}");
    }

    #[test]
    fn truncated_body_is_an_error() {
        let err = Response::read_from(&b"OK-BYTES 10\nshort"[..]).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::UnexpectedEof);
    }

    #[test]
    fn non_numeric_body_length_is_an_error() {
        let err = Response::read_from(&b"OK-BYTES lots\n"[..]).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }

    // ── framing ──────────────────────────────────────────────────────────────

    #[test]
    fn reads_one_line_and_leaves_the_rest() {
        let line = read_framed_line(&b"first\nsecond\n"[..]).unwrap();
        assert_eq!(line, Some("first".to_owned()));
    }

    /// `--status` connects and closes; that must not look like a failure.
    #[test]
    fn empty_stream_is_a_probe_not_an_error() {
        assert_eq!(read_framed_line(&b""[..]).unwrap(), None);
        assert_eq!(Response::read_from(&b""[..]).unwrap(), None);
    }

    #[test]
    fn read_fails_when_peer_closes_mid_line() {
        let err = read_framed_line(&b"no newline here"[..]).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn read_fails_on_overlong_line() {
        let flood = vec![b'a'; MAX_LINE + 10];
        let err = read_framed_line(&flood[..]).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn request_survives_the_round_trip() {
        let url = "https://example.com/a?b=1&c=2#d";
        let mut wire = Vec::new();
        Request::Open(normalize(url).unwrap())
            .write_to(&mut wire)
            .unwrap();
        let line = read_framed_line(&wire[..]).unwrap().unwrap();
        assert_eq!(
            Request::parse(&line).unwrap(),
            Request::Open(url.to_owned())
        );
    }
}
