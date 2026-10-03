//! Listening TCP sockets of the VM, read from /proc/net/tcp{,6}. Only used by
//! `--check`, which probes each one from inside the sandbox.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

const LISTEN: &str = "0A";

/// Every listening socket; wildcard binds map to loopback,
/// since that is how a sandboxed process would try to reach them.
pub fn listening() -> Vec<SocketAddr> {
    let mut out = Vec::new();
    for file in ["/proc/net/tcp", "/proc/net/tcp6"] {
        if let Ok(text) = std::fs::read_to_string(file) {
            out.extend(text.lines().skip(1).filter_map(parse_line));
        }
    }
    out.sort();
    out.dedup();
    out
}

fn parse_line(line: &str) -> Option<SocketAddr> {
    let mut fields = line.split_whitespace();
    let local = fields.nth(1)?;
    let state = fields.nth(1)?;
    if state != LISTEN {
        return None;
    }
    let (addr, port) = local.split_once(':')?;
    let port = u16::from_str_radix(port, 16).ok()?;
    let mut ip = parse_addr(addr)?;
    if ip.is_unspecified() {
        ip = if ip.is_ipv4() {
            Ipv4Addr::LOCALHOST.into()
        } else {
            Ipv6Addr::LOCALHOST.into()
        };
    }
    Some(SocketAddr::new(ip, port))
}

/// The kernel prints each 32-bit word of the address in host byte order.
fn parse_addr(hex: &str) -> Option<IpAddr> {
    let word = |i: usize| -> Option<[u8; 4]> {
        Some(
            u32::from_str_radix(hex.get(i * 8..i * 8 + 8)?, 16)
                .ok()?
                .to_ne_bytes(),
        )
    };
    match hex.len() {
        8 => Some(Ipv4Addr::from(word(0)?).into()),
        32 => {
            let mut b = [0u8; 16];
            for i in 0..4 {
                b[i * 4..i * 4 + 4].copy_from_slice(&word(i)?);
            }
            Some(Ipv6Addr::from(b).into())
        }
        _ => None,
    }
}

#[cfg(all(test, target_endian = "little"))]
mod tests {
    use super::*;

    #[test]
    fn parses_v4_listen() {
        let l = "   0: 0100007F:2405 00000000:0000 0A 00000000:00000000 00:00000000 00000000   501 0 1 1";
        assert_eq!(parse_line(l), "127.0.0.1:9221".parse().ok());
    }

    #[test]
    fn wildcard_maps_to_loopback_and_skips_non_listen() {
        let l = "   1: 00000000:0BB8 00000000:0000 0A 0 0 0";
        assert_eq!(parse_line(l), "127.0.0.1:3000".parse().ok());
        let est = "   2: 0100007F:0BB8 0100007F:D431 01 0 0 0";
        assert_eq!(parse_line(est), None);
    }

    #[test]
    fn parses_v6_loopback() {
        let l = "   0: 00000000000000000000000001000000:0016 00000000000000000000000000000000:0000 0A 0";
        assert_eq!(parse_line(l), "[::1]:22".parse().ok());
    }
}
