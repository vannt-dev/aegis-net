//! DNS-over-TLS upstream transport (RFC 7858).
//!
//! A DoT upstream is written `tls://<host>[:port][#<name>]` (or `dot://`):
//!
//! * `tls://1.1.1.1` connects to the address and verifies the certificate
//!   against the address itself, which works for resolvers whose certificate
//!   carries an IP subject alternative name.
//! * `tls://94.140.14.14#dns.adguard-dns.com` connects to the address and
//!   verifies the certificate against the name after `#`.
//! * `tls://dns.example` connects to the name. Resolving it goes through the
//!   system resolver, which on a device is this engine: prefer one of the two
//!   address forms there, as with a DoH upstream.

use rustls::pki_types::ServerName;
use rustls::{ClientConfig, ClientConnection, RootCertStore, StreamOwned};
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const DEFAULT_PORT: u16 = 853;

/// Matches the DoH agent: a dead upstream must be noticed before the client
/// gives up on its own.
const IO_TIMEOUT: Duration = Duration::from_millis(2500);

/// One idle connection per worker thread is the most that can ever be used.
const MAX_IDLE_CONNECTIONS: usize = 8;

const DNS_HEADER_LEN: usize = 12;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DotTarget {
    /// Host or address to connect to.
    pub host: String,
    pub port: u16,
    /// Name or address the server certificate must be valid for.
    pub server_name: String,
}

/// Whether `upstream` names a DoT resolver at all, well-formed or not.
pub fn is_dot_scheme(upstream: &str) -> bool {
    upstream.starts_with("tls://") || upstream.starts_with("dot://")
}

/// Parse a `tls://` / `dot://` upstream. Returns None for any other scheme and
/// for a target that is not a bare host with an optional port and `#name`.
pub fn parse_target(upstream: &str) -> Option<DotTarget> {
    let rest = upstream
        .strip_prefix("tls://")
        .or_else(|| upstream.strip_prefix("dot://"))?;
    let rest = rest.strip_suffix('/').unwrap_or(rest);

    let (address, name) = match rest.split_once('#') {
        Some((address, name)) => (address, Some(name)),
        None => (rest, None),
    };
    if address.is_empty() || address.contains(['/', '?', '@', ' ']) {
        return None;
    }

    let (host, port) = if let Some(bracketed) = address.strip_prefix('[') {
        // [2606:4700:4700::1111] or [2606:4700:4700::1111]:853
        let (host, after) = bracketed.split_once(']')?;
        match after.strip_prefix(':') {
            Some(port) => (host, port.parse().ok()?),
            None if after.is_empty() => (host, DEFAULT_PORT),
            None => return None,
        }
    } else {
        match address.rsplit_once(':') {
            // More than one colon and no brackets is a bare IPv6 address.
            Some((host, _)) if host.contains(':') => (address, DEFAULT_PORT),
            Some((host, port)) => (host, port.parse().ok()?),
            None => (address, DEFAULT_PORT),
        }
    };
    if host.is_empty() || port == 0 {
        return None;
    }

    let server_name = match name {
        Some(name) if !name.is_empty() => name,
        Some(_) => return None,
        None => host,
    };
    // Reject here what the TLS layer would reject on every single query.
    ServerName::try_from(server_name.to_string()).ok()?;

    Some(DotTarget {
        host: host.to_string(),
        port,
        server_name: server_name.to_string(),
    })
}

type Connection = StreamOwned<ClientConnection, TcpStream>;

pub struct DotClient {
    config: Arc<ClientConfig>,
    idle: Mutex<Vec<(DotTarget, Connection)>>,
}

impl Default for DotClient {
    fn default() -> Self {
        Self::new()
    }
}

impl DotClient {
    /// A client trusting the bundled Mozilla root certificates.
    pub fn new() -> Self {
        let mut roots = RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        Self::with_roots(roots)
    }

    pub fn with_roots(roots: RootCertStore) -> Self {
        // Named explicitly rather than taken from the process default, so a
        // second crypto backend linked in by some other crate cannot make the
        // builder panic at first use.
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let config = ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .expect("ring supports the default TLS versions")
            .with_root_certificates(roots)
            .with_no_client_auth();
        Self {
            config: Arc::new(config),
            idle: Mutex::new(Vec::new()),
        }
    }

    /// Send one DNS wire message and return the answer, or None when the
    /// resolver could not be reached, failed verification, or answered with
    /// something that is not a reply to this query.
    pub fn exchange(&self, target: &DotTarget, query: &[u8]) -> Option<Vec<u8>> {
        if query.len() < DNS_HEADER_LEN || query.len() > usize::from(u16::MAX) {
            return None;
        }

        // An idle connection may have been closed by the resolver since it was
        // last used; that only shows on the next write or read, so a failure
        // on a reused connection is retried once on a fresh one.
        if let Some(mut connection) = self.take_idle(target) {
            if let Some(answer) = Self::round_trip(&mut connection, query) {
                self.keep(target, connection);
                return Some(answer);
            }
        }

        let mut connection = self.connect(target)?;
        let answer = Self::round_trip(&mut connection, query)?;
        self.keep(target, connection);
        Some(answer)
    }

    fn take_idle(&self, target: &DotTarget) -> Option<Connection> {
        let mut idle = self.idle.lock().unwrap();
        // Connections to a resolver that is no longer configured are dropped.
        idle.retain(|(owner, _)| owner == target);
        idle.pop().map(|(_, connection)| connection)
    }

    fn keep(&self, target: &DotTarget, connection: Connection) {
        let mut idle = self.idle.lock().unwrap();
        if idle.len() < MAX_IDLE_CONNECTIONS {
            idle.push((target.clone(), connection));
        }
    }

    fn connect(&self, target: &DotTarget) -> Option<Connection> {
        let server_name = ServerName::try_from(target.server_name.clone()).ok()?;
        let addresses = (target.host.as_str(), target.port).to_socket_addrs().ok()?;
        for address in addresses {
            let Ok(socket) = TcpStream::connect_timeout(&address, IO_TIMEOUT) else {
                continue;
            };
            if socket.set_read_timeout(Some(IO_TIMEOUT)).is_err()
                || socket.set_write_timeout(Some(IO_TIMEOUT)).is_err()
            {
                continue;
            }
            // The whole message goes out in one write; do not hold it back.
            let _ = socket.set_nodelay(true);
            let Ok(session) = ClientConnection::new(self.config.clone(), server_name.clone())
            else {
                return None;
            };
            return Some(StreamOwned::new(session, socket));
        }
        None
    }

    /// RFC 7858 frames each message as RFC 1035 TCP does: a two-octet length,
    /// then the message.
    fn round_trip(connection: &mut Connection, query: &[u8]) -> Option<Vec<u8>> {
        let mut frame = Vec::with_capacity(query.len() + 2);
        frame.extend_from_slice(&(query.len() as u16).to_be_bytes());
        frame.extend_from_slice(query);
        connection.write_all(&frame).ok()?;
        connection.flush().ok()?;

        let mut length = [0u8; 2];
        connection.read_exact(&mut length).ok()?;
        let length = usize::from(u16::from_be_bytes(length));
        if length < DNS_HEADER_LEN {
            return None;
        }
        let mut answer = vec![0u8; length];
        connection.read_exact(&mut answer).ok()?;

        // The transaction id ties the answer to the question. A mismatch means
        // the stream is out of step and nothing read from it can be trusted.
        if answer[0..2] != query[0..2] {
            return None;
        }
        Some(answer)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rustls::pki_types::pem::PemObject;
    use rustls::pki_types::{CertificateDer, PrivateKeyDer};
    use rustls::{ServerConfig, ServerConnection};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::thread;

    const CERT_PEM: &[u8] = include_bytes!("../tests/data/dot-test-cert.pem");
    const KEY_PEM: &[u8] = include_bytes!("../tests/data/dot-test-key.pem");

    fn query(id: u16) -> Vec<u8> {
        let mut message = id.to_be_bytes().to_vec();
        message.extend_from_slice(&[0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        message.extend_from_slice(&[
            7, b'e', b'x', b'a', b'm', b'p', b'l', b'e', 3, b'c', b'o', b'm', 0,
        ]);
        message.extend_from_slice(&[0, 1, 0, 1]);
        message
    }

    #[derive(Clone, Copy, PartialEq)]
    enum Behaviour {
        /// Answer every query on the connection.
        KeepOpen,
        /// Answer one query, then close.
        CloseAfterOne,
        /// Answer with a different transaction id.
        WrongId,
        /// Announce a message shorter than a DNS header.
        ShortAnswer,
    }

    struct TestServer {
        port: u16,
        connections: Arc<AtomicUsize>,
    }

    /// A DoT server on loopback that echoes each query back with the QR bit set.
    fn serve(behaviour: Behaviour) -> TestServer {
        let certificate = CertificateDer::from_pem_slice(CERT_PEM).unwrap();
        let key = PrivateKeyDer::from_pem_slice(KEY_PEM).unwrap();
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let config = Arc::new(
            ServerConfig::builder_with_provider(provider)
                .with_safe_default_protocol_versions()
                .unwrap()
                .with_no_client_auth()
                .with_single_cert(vec![certificate], key)
                .unwrap(),
        );
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let connections = Arc::new(AtomicUsize::new(0));
        let counter = connections.clone();

        thread::spawn(move || {
            for socket in listener.incoming() {
                let Ok(socket) = socket else { break };
                counter.fetch_add(1, Ordering::SeqCst);
                let config = config.clone();
                thread::spawn(move || {
                    let session = ServerConnection::new(config).unwrap();
                    let mut stream = StreamOwned::new(session, socket);
                    loop {
                        let mut length = [0u8; 2];
                        if stream.read_exact(&mut length).is_err() {
                            return;
                        }
                        let mut message = vec![0u8; usize::from(u16::from_be_bytes(length))];
                        if stream.read_exact(&mut message).is_err() {
                            return;
                        }
                        message[2] |= 0x80;
                        match behaviour {
                            Behaviour::WrongId => message[1] ^= 0xff,
                            Behaviour::ShortAnswer => message.truncate(4),
                            _ => {}
                        }
                        let mut frame = (message.len() as u16).to_be_bytes().to_vec();
                        frame.extend_from_slice(&message);
                        if stream.write_all(&frame).is_err() || stream.flush().is_err() {
                            return;
                        }
                        if behaviour == Behaviour::CloseAfterOne {
                            stream.conn.send_close_notify();
                            let _ = stream.flush();
                            return;
                        }
                    }
                });
            }
        });

        TestServer { port, connections }
    }

    fn client() -> DotClient {
        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from_pem_slice(CERT_PEM).unwrap())
            .unwrap();
        DotClient::with_roots(roots)
    }

    fn target(port: u16, server_name: &str) -> DotTarget {
        DotTarget {
            host: "127.0.0.1".to_string(),
            port,
            server_name: server_name.to_string(),
        }
    }

    #[test]
    fn parses_addresses_ports_and_verification_names() {
        let parsed =
            |upstream: &str| parse_target(upstream).map(|t| (t.host, t.port, t.server_name));
        let expect =
            |host: &str, port: u16, name: &str| Some((host.to_string(), port, name.to_string()));

        assert_eq!(parsed("tls://1.1.1.1"), expect("1.1.1.1", 853, "1.1.1.1"));
        assert_eq!(parsed("dot://1.1.1.1/"), expect("1.1.1.1", 853, "1.1.1.1"));
        assert_eq!(
            parsed("tls://9.9.9.9:8853"),
            expect("9.9.9.9", 8853, "9.9.9.9")
        );
        assert_eq!(
            parsed("tls://dns.adguard-dns.com"),
            expect("dns.adguard-dns.com", 853, "dns.adguard-dns.com")
        );
        assert_eq!(
            parsed("tls://94.140.14.14#dns.adguard-dns.com"),
            expect("94.140.14.14", 853, "dns.adguard-dns.com")
        );
        assert_eq!(
            parsed("tls://94.140.14.14:853#dns.adguard-dns.com"),
            expect("94.140.14.14", 853, "dns.adguard-dns.com")
        );
        assert_eq!(
            parsed("tls://[2606:4700:4700::1111]"),
            expect("2606:4700:4700::1111", 853, "2606:4700:4700::1111")
        );
        assert_eq!(
            parsed("tls://[2606:4700:4700::1111]:8853#one.one.one.one"),
            expect("2606:4700:4700::1111", 8853, "one.one.one.one")
        );
        assert_eq!(
            parsed("tls://2606:4700:4700::1111"),
            expect("2606:4700:4700::1111", 853, "2606:4700:4700::1111")
        );
    }

    #[test]
    fn rejects_other_schemes_and_malformed_targets() {
        for upstream in [
            "1.1.1.1",
            "https://1.1.1.1/dns-query",
            "tls://",
            "tls://#name",
            "tls://1.1.1.1#",
            "tls://1.1.1.1:0",
            "tls://1.1.1.1:port",
            "tls://1.1.1.1:99999",
            "tls://1.1.1.1/dns-query",
            "tls://user@1.1.1.1",
            "tls://[::1",
            "tls://[::1]x",
            "tls://1.1.1.1#not a name",
        ] {
            assert_eq!(parse_target(upstream), None, "{upstream}");
        }
        assert!(is_dot_scheme("tls://"));
        assert!(is_dot_scheme("dot://anything"));
        assert!(!is_dot_scheme("https://1.1.1.1/dns-query"));
    }

    #[test]
    fn answers_over_tls_and_reuses_the_connection() {
        let server = serve(Behaviour::KeepOpen);
        let client = client();
        let target = target(server.port, "127.0.0.1");

        for id in [0x1001u16, 0x1002, 0x1003] {
            let answer = client.exchange(&target, &query(id)).expect("an answer");
            assert_eq!(answer[0..2], id.to_be_bytes());
            assert_eq!(answer[2] & 0x80, 0x80, "QR bit set by the server");
            assert_eq!(answer.len(), query(id).len());
        }
        assert_eq!(server.connections.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn verifies_the_certificate_against_the_name_after_the_hash() {
        let server = serve(Behaviour::KeepOpen);
        let client = client();

        assert!(client
            .exchange(&target(server.port, "dot.test"), &query(1))
            .is_some());
        assert!(
            client
                .exchange(&target(server.port, "other.test"), &query(2))
                .is_none(),
            "a certificate for another name must not be accepted"
        );
    }

    #[test]
    fn rejects_a_server_no_trusted_root_vouches_for() {
        let server = serve(Behaviour::KeepOpen);
        // The public roots know nothing about the test certificate.
        let client = DotClient::new();

        assert!(client
            .exchange(&target(server.port, "127.0.0.1"), &query(1))
            .is_none());
    }

    #[test]
    fn reconnects_when_the_resolver_closed_an_idle_connection() {
        let server = serve(Behaviour::CloseAfterOne);
        let client = client();
        let target = target(server.port, "127.0.0.1");

        assert!(client.exchange(&target, &query(1)).is_some());
        assert!(client.exchange(&target, &query(2)).is_some());
        assert_eq!(server.connections.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn drops_idle_connections_to_a_resolver_that_is_no_longer_configured() {
        let first = serve(Behaviour::KeepOpen);
        let second = serve(Behaviour::KeepOpen);
        let client = client();

        assert!(client
            .exchange(&target(first.port, "127.0.0.1"), &query(1))
            .is_some());
        assert!(client
            .exchange(&target(second.port, "127.0.0.1"), &query(2))
            .is_some());
        assert!(client
            .exchange(&target(first.port, "127.0.0.1"), &query(3))
            .is_some());

        assert_eq!(first.connections.load(Ordering::SeqCst), 2);
        assert_eq!(second.connections.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn refuses_an_answer_to_a_different_question_or_a_truncated_one() {
        for behaviour in [Behaviour::WrongId, Behaviour::ShortAnswer] {
            let server = serve(behaviour);
            let client = client();
            assert!(client
                .exchange(&target(server.port, "127.0.0.1"), &query(0x4242))
                .is_none());
        }
    }

    #[test]
    fn gives_up_on_an_unreachable_resolver_and_on_a_malformed_query() {
        let client = client();
        // Port 1 on loopback refuses at once.
        assert!(client
            .exchange(&target(1, "127.0.0.1"), &query(1))
            .is_none());

        let server = serve(Behaviour::KeepOpen);
        assert!(client
            .exchange(&target(server.port, "127.0.0.1"), &[0u8; 4])
            .is_none());
        assert_eq!(server.connections.load(Ordering::SeqCst), 0);
    }

    /// Talks to real resolvers; run with `cargo test -- --ignored`.
    #[test]
    #[ignore = "needs network access to public DoT resolvers"]
    fn resolves_through_public_resolvers() {
        let client = DotClient::new();
        for upstream in [
            "tls://1.1.1.1",
            "tls://8.8.8.8#dns.google",
            "tls://9.9.9.9#dns.quad9.net",
        ] {
            let target = parse_target(upstream).unwrap();
            let answer = client
                .exchange(&target, &query(0x7a7a))
                .unwrap_or_else(|| panic!("no answer from {upstream}"));
            assert_eq!(answer[3] & 0x0f, 0, "{upstream}: expected NOERROR");
            let answers = u16::from_be_bytes([answer[6], answer[7]]);
            assert!(answers > 0, "{upstream}: expected at least one record");
        }
    }
}
