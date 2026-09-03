//! Shared core for the two halves of the devbox URL opener.
//!
//! The guest VM has no desktop, so nothing there provides `xdg-open` — which is
//! what lazygit, `nvim gx`, `gh browse` and friends all shell out to. This crate
//! ships a replacement `xdg-open` for the guest that hands the URL to a small
//! daemon on the Mac, which calls `/usr/bin/open`.
//!
//! Both halves link this library so that URL validation and the wire format are
//! defined exactly once. If they were duplicated, they would drift, and a
//! disagreement between the two ends is precisely the kind of bug that shows up
//! months later as "that one link doesn't work".
//!
//! ## The wire format
//!
//! One request per connection, newline-framed, ASCII:
//!
//! ```text
//! -> https://github.com/owner/repo/pull/42\n
//! <- OK\n                        (or)  ERR <reason>\n
//! ```
//!
//! Newline framing is only safe because [`normalize`] rejects every byte below
//! `0x21`, so a URL can never contain the `\n` that terminates it. The two rules
//! are load-bearing for each other — see the note in [`normalize`].
//!
//! ## Rust notes for the reader
//!
//! - `&str` is a borrowed string slice, `String` is owned.
//! - `Result<T, E>` is "a T or an error E"; `?` after a fallible call returns
//!   the error to the caller, like rethrowing in a try/catch language.
//! - `enum` in Rust is a *tagged union*: [`Rejection`] is exactly one of its
//!   variants, and each variant can carry different data. `match` on it is
//!   checked for exhaustiveness at compile time, so adding a variant later
//!   forces every handler to be updated.
//! - `impl Display for X` is how a type opts into `{}` formatting. It is the
//!   idiomatic place to put a human-readable error message, rather than building
//!   strings at each call site.
//! - `impl<R: Read>` means "for any type that can be read from" — a `TcpStream`
//!   in production, a `Cursor` over a byte array in the tests below.

use std::fmt;
use std::io::{self, BufRead, BufReader, Read, Write};

/// Loopback port for the daemon.
///
/// Also hardcoded in `devbox/scripts/ssh-config.sh` as the `RemoteForward`
/// endpoint, and in `devbox/README.md`. Changing it here means changing it
/// there and re-pasting the SSH config block.
pub const PORT: u16 = 17325;

/// The daemon binds loopback only, and the guest reaches it through the SSH
/// reverse tunnel rather than over the network.
pub const HOST: &str = "127.0.0.1";

/// Longest URL accepted. Comfortably above anything GitHub, Jira or Confluence
/// produce; the point is to have *a* bound so a hostile or buggy caller cannot
/// make the daemon allocate without limit.
pub const MAX_LEN: usize = 2048;

/// Longest line either side will read, request or response. A response is
/// `"ERR "` plus a [`Rejection`] message, so it needs headroom over [`MAX_LEN`].
pub const MAX_LINE: usize = MAX_LEN + 256;

// ─────────────────────────────────────────────────────────────────────────────
// Validation
// ─────────────────────────────────────────────────────────────────────────────

/// Why a URL was refused.
///
/// Carries the offending byte and its offset where relevant, because "your URL
/// was rejected" with no detail is useless when it happens six months from now
/// inside lazygit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Rejection {
    /// No argument, or an argument that was entirely whitespace.
    Empty,
    /// Longer than [`MAX_LEN`].
    TooLong { len: usize },
    /// Did not begin with `http://` or `https://`.
    NotHttp,
    /// Nothing between the `://` and the first `/`, `?` or `#`.
    NoHost,
    /// A byte >= 0x80: the URL is not pure ASCII.
    NonAscii { byte: u8, at: usize },
    /// A control byte, or a raw space, both of which have no place in a URL on
    /// the wire — and would break newline framing in the case of `\n`.
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

/// Check a URL and return the form to put on the wire.
///
/// Today this only validates and copies, but it deliberately returns an owned
/// `String` rather than borrowing the input. That is the seam for a future
/// upgrade: if the ASCII-only restriction below ever becomes a real problem, the
/// fix is to add the `url` crate to `[workspace.dependencies]` and replace this
/// function body with
///
/// ```text
/// let parsed = Url::parse(input).map_err(..)?;
/// // check scheme + host, then:
/// Ok(parsed.as_str().to_owned())   // guaranteed ASCII: IDN punycoded,
///                                  // path percent-encoded
/// ```
///
/// which changes this body and nothing else. Returning `&str` today would have
/// forced every call site to change at that point instead. See `Cargo.toml` for
/// why that dependency was not taken now.
///
/// The checks, in order, and what each one is actually for:
///
/// 1. **non-empty**, so a bare `xdg-open` gives a usage error not a parse error.
/// 2. **length**, to bound allocation.
/// 3. **`http://` or `https://` prefix**. This single rule does three jobs: it
///    restricts schemes to the two that make sense; it guarantees the string
///    cannot start with `-`, so `/usr/bin/open` can never read it as a flag;
///    and it guarantees it is not a bare path, so `open` cannot be tricked into
///    opening a local file or application.
/// 4. **every byte in `0x21..=0x7E`**. Rejects non-ASCII (the documented
///    limitation) and, just as importantly, rejects `\n` — without which the
///    newline framing in [`read_framed_line`] could be smuggled past.
/// 5. **non-empty host**, so `https://` alone or `https:///path` is refused.
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

    // Byte-wise, not char-wise: we are asserting the string is pure ASCII, and
    // `bytes()` reports the true offset of the first offending byte. Iterating
    // `chars()` would give a char index, which is not what a reader needs in
    // order to find the problem.
    for (at, byte) in url.bytes().enumerate() {
        match byte {
            0x21..=0x7e => {}
            0x80.. => return Err(Rejection::NonAscii { byte, at }),
            _ => return Err(Rejection::Forbidden { byte, at }),
        }
    }

    // The authority runs to the first `/`, `?` or `#`. Anything before a `@` is
    // userinfo, so `https://@example.com` still has a host but
    // `https://user@` does not.
    let authority = rest.find(['/', '?', '#']).map_or(rest, |end| &rest[..end]);
    let host = authority.rsplit('@').next().unwrap_or("");
    if host.is_empty() {
        return Err(Rejection::NoHost);
    }

    Ok(url.to_owned())
}

/// Return everything after `http://` or `https://`, or `None` for any other
/// scheme.
///
/// Scheme comparison is ASCII-case-insensitive because `HTTPS://x.com` is a
/// valid URL, but the check runs before the ASCII check above, so it must not
/// assume ASCII input — `eq_ignore_ascii_case` is safe on arbitrary bytes,
/// whereas `to_lowercase()` would allocate and apply Unicode rules.
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

    /// Parse a line produced by [`Response::encode`], with the newline already
    /// stripped by [`read_framed_line`].
    ///
    /// An unrecognised line is reported as an error rather than silently
    /// treated as success: if the two halves ever disagree about the protocol,
    /// failing loudly beats opening nothing and claiming victory.
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

/// Read one newline-terminated line, at most [`MAX_LINE`] bytes, with the
/// newline stripped.
///
/// Three outcomes, deliberately distinguished:
///
/// - `Ok(Some(line))` — a complete line arrived.
/// - `Ok(None)` — the peer connected and closed without sending a byte. This is
///   a *liveness probe*, not a failure: it is exactly what
///   `devbox-open-url --status` does to prove something is listening. Folding
///   it in with the error case below fills the daemon's log with alarming
///   "read failed" lines every time the status check runs.
/// - `Err(..)` — a partial line then EOF, or no newline within [`MAX_LINE`]
///   bytes. A truncated URL must never be treated as a short one: `open` would
///   happily act on the truncation.
///
/// Bounded by wrapping the reader in [`Read::take`], so a peer that never sends
/// a newline cannot make this allocate forever.
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

    /// The shape of link that started all this: a pull request opened from
    /// lazygit with `o`.
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

    /// The reason the scheme check exists at all: a leading `-` would otherwise
    /// be parsed as a flag by `/usr/bin/open`.
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

    /// Framing safety: an embedded newline must not be able to smuggle a second
    /// request past the daemon.
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

    /// The documented ASCII-only limitation, recorded as a test rather than a
    /// comment. If the `url` crate is ever adopted (see `normalize`), this test
    /// flips from "rejected" to "percent-encoded as
    /// `.../wiki/Bahnhofstra%C3%9Fe`" and proves the upgrade landed.
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

    /// A connect-and-close is how `devbox-open-url --status` probes liveness.
    /// It must not look like a failed request, or every status check would log
    /// an error on the daemon side.
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

    /// End-to-end through the wire helpers: the client's bytes are what the
    /// daemon reads back.
    #[test]
    fn request_survives_the_round_trip() {
        let url = "https://example.com/a?b=1&c=2#d";
        let mut wire = Vec::new();
        write_request(&mut wire, &normalize(url).unwrap()).unwrap();
        assert_eq!(read_framed_line(&wire[..]).unwrap().as_deref(), Some(url));
    }
}
