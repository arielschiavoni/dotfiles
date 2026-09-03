//! Shared core for the two halves of the devbox URL opener.
//!
//! The headless guest has no `xdg-open`, which is what lazygit, `nvim gx` and
//! `gh browse` all shell out to. This crate ships a replacement for the guest
//! that hands the URL to a daemon on the Mac, which calls `/usr/bin/open`.
//!
//! Both halves link this library, so validation and framing are defined once
//! and cannot drift apart.
//!
//! Wire format — one request per connection, newline-framed, ASCII:
//!
//! ```text
//! -> https://github.com/owner/repo/pull/42\n
//! <- OK\n                        (or)  ERR <reason>\n
//! ```
//!
//! Framing is safe only because [`normalize`] rejects bytes below `0x21`, so a
//! URL can never contain the terminating `\n`.

use std::fmt;
use std::io::{self, BufRead, BufReader, Read, Write};

/// Loopback port. Also hardcoded in `devbox/scripts/ssh-config.sh` as the
/// `RemoteForward` endpoint; change both together.
pub const PORT: u16 = 17325;

/// Loopback only — the guest arrives via the SSH reverse tunnel.
pub const HOST: &str = "127.0.0.1";

/// Longest URL accepted. Bounds allocation only; the read is separately
/// bounded by [`Read::take`]. 8 KiB rather than the usual 2048 because OAuth
/// and especially SAML redirects can run to several kilobytes, and a refused
/// login looks like a broken tool rather than a policy decision.
pub const MAX_LEN: usize = 8192;

/// Longest line either side will read. A response is `"ERR "` plus a
/// [`Rejection`] message, so it needs headroom over [`MAX_LEN`].
pub const MAX_LINE: usize = MAX_LEN + 256;

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
/// Checks: non-empty; within [`MAX_LEN`]; `http://` or `https://` prefix;
/// every byte in `0x21..=0x7E`; non-empty host.
///
/// The prefix check does three jobs — it limits schemes, guarantees the string
/// cannot start with `-` (so `open` cannot read it as a flag), and guarantees
/// it is not a bare path (so `open` cannot be steered to a local file). The
/// byte-range check rejects non-ASCII, the documented limitation, and `\n`,
/// which would break the wire framing.
///
/// Returns an owned `String` although it currently only copies: that is the
/// seam for swapping in the `url` crate later (see `Cargo.toml`), which would
/// then change this body and no call sites.
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
///
/// `eq_ignore_ascii_case` because `HTTPS://` is valid, and because this runs
/// before the ASCII check so it must be safe on arbitrary bytes.
fn strip_scheme(url: &str) -> Option<&str> {
    for prefix in ["http://", "https://"] {
        if url.len() >= prefix.len() && url[..prefix.len()].eq_ignore_ascii_case(prefix) {
            return Some(&url[prefix.len()..]);
        }
    }
    None
}

// ─────────────────────────────────────────────────────────────────────────────
// Wire format
// ─────────────────────────────────────────────────────────────────────────────

/// The daemon's answer to a request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Response {
    /// Handed to `/usr/bin/open` successfully.
    Ok,
    /// Refused, or failed to launch. The string is already human-readable.
    Err(String),
}

impl Response {
    /// Render as a single framed line, newline included.
    pub fn encode(&self) -> String {
        match self {
            Response::Ok => "OK\n".to_owned(),
            // A reason containing a newline would desynchronise the framing, so
            // flatten any that sneak in from an OS error string.
            Response::Err(reason) => format!("ERR {}\n", reason.replace('\n', " ")),
        }
    }

    /// Parse a line from [`Response::encode`], newline already stripped. An
    /// unrecognised line becomes an error rather than a silent success.
    pub fn parse(line: &str) -> Response {
        if line == "OK" {
            Response::Ok
        } else if let Some(reason) = line.strip_prefix("ERR ") {
            Response::Err(reason.to_owned())
        } else {
            Response::Err(format!("unrecognised response from daemon: {line:?}"))
        }
    }
}

/// Write a request line: the URL, then `\n`.
pub fn write_request<W: Write>(mut writer: W, url: &str) -> io::Result<()> {
    writer.write_all(url.as_bytes())?;
    writer.write_all(b"\n")?;
    writer.flush()
}

/// Read one newline-terminated line, at most [`MAX_LINE`] bytes, newline
/// stripped.
///
/// `Ok(None)` means the peer connected and closed without sending anything — a
/// liveness probe, which is what `devbox-open-url --status` does. Treating that
/// as an error would fill the daemon log on every status check. `Err` means a
/// partial or overlong line; a truncated URL must never pass as a short one.
pub fn read_framed_line<R: Read>(reader: R) -> io::Result<Option<String>> {
    let mut buf = Vec::new();
    let mut limited = BufReader::new(reader.take(MAX_LINE as u64 + 1));
    limited.read_until(b'\n', &mut buf)?;

    if buf.is_empty() {
        return Ok(None);
    }

    if buf.last() != Some(&b'\n') {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "no newline within {MAX_LINE} bytes after {} bytes \
                 (peer closed mid-line, or line too long)",
                buf.len()
            ),
        ));
    }
    buf.pop();

    String::from_utf8(buf)
        .map(Some)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
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

    /// The shape of link that started all this.
    #[test]
    fn accepts_github_pull_request() {
        let url = "https://github.com/owner/repo/pull/42";
        assert_eq!(normalize(url).unwrap(), url);
    }

    /// Query and fragment must survive byte-for-byte. `&` and `#` are exactly
    /// what a naive shell-based implementation would mangle.
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

    /// `open` would treat this as a local file path, so it must never reach it.
    #[test]
    fn rejects_file_scheme() {
        assert_eq!(
            normalize("file:///etc/passwd").unwrap_err(),
            Rejection::NotHttp
        );
    }

    /// Why the scheme check exists: `open` would read this as a flag.
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

    /// The ASCII-only limitation, pinned as a test rather than a comment. If
    /// the `url` crate is ever adopted this flips to "percent-encoded".
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

    /// Likewise for an internationalised host, which would need Punycode.
    #[test]
    fn rejects_idn_host_for_now() {
        let err = normalize("https://bücher.example/x").unwrap_err();
        assert!(matches!(err, Rejection::NonAscii { .. }), "{err:?}");
    }

    // ── wire format ──────────────────────────────────────────────────────────

    #[test]
    fn response_round_trips() {
        for original in [
            Response::Ok,
            Response::Err("must start with http:// or https://".to_owned()),
        ] {
            let encoded = original.encode();
            assert!(encoded.ends_with('\n'));
            let line = encoded.trim_end_matches('\n');
            assert_eq!(Response::parse(line), original);
        }
    }

    #[test]
    fn response_flattens_newlines_in_reason() {
        let encoded = Response::Err("two\nlines".to_owned()).encode();
        assert_eq!(encoded, "ERR two lines\n");
        assert_eq!(encoded.matches('\n').count(), 1);
    }

    #[test]
    fn unrecognised_response_is_an_error_not_a_success() {
        assert!(matches!(Response::parse("banana"), Response::Err(_)));
        assert!(matches!(Response::parse(""), Response::Err(_)));
    }

    #[test]
    fn request_is_newline_framed() {
        let mut out = Vec::new();
        write_request(&mut out, "https://example.com").unwrap();
        assert_eq!(out, b"https://example.com\n");
    }

    #[test]
    fn reads_one_line_and_leaves_the_rest() {
        let line = read_framed_line(&b"first\nsecond\n"[..]).unwrap();
        assert_eq!(line, Some("first".to_owned()));
    }

    /// `--status` probes liveness by connecting and closing; that must not
    /// look like a failed request.
    #[test]
    fn empty_stream_is_a_probe_not_an_error() {
        assert_eq!(read_framed_line(&b""[..]).unwrap(), None);
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

    /// The client's bytes are what the daemon reads back.
    #[test]
    fn request_survives_the_round_trip() {
        let url = "https://example.com/a?b=1&c=2#d";
        let mut wire = Vec::new();
        write_request(&mut wire, &normalize(url).unwrap()).unwrap();
        assert_eq!(read_framed_line(&wire[..]).unwrap().as_deref(), Some(url));
    }
}
