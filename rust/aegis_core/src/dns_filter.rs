use std::net::SocketAddr;
use std::sync::Arc;
use log::{info, debug};
use crate::rule_engine::RuleEngine;
use crate::statistics::StatisticsEngine;
use crate::cache::DnsCache;

pub struct DnsFilterService {
    rule_engine: Arc<RuleEngine>,
    stats_engine: Arc<StatisticsEngine>,
    dns_cache: Arc<DnsCache>,
    upstream_dns: String,
    safesearch_enabled: bool,
}

impl DnsFilterService {
    pub fn new(
        rule_engine: Arc<RuleEngine>,
        stats_engine: Arc<StatisticsEngine>,
        upstream_dns: String,
    ) -> Self {
        Self {
            rule_engine,
            stats_engine,
            dns_cache: Arc::new(DnsCache::new(300)), // 5 minute TTL cache
            upstream_dns,
            safesearch_enabled: true,
        }
    }

    pub fn handle_dns_payload(&self, payload: &[u8], _client_addr: SocketAddr) -> Vec<u8> {
        let question = Self::extract_question(payload);

        if let Some((domain, qtype)) = question {
            // 1. Check SafeSearch Enforcement
            if self.safesearch_enabled {
                if let Some(safe_resp) = Self::handle_safesearch_rewrite(&domain, payload) {
                    info!("SAFESEARCH Rewritten: {}", domain);
                    self.stats_engine.record_request(&domain, false);
                    return safe_resp;
                }
            }

            // 2. Check Rule Engine Blocking
            let is_blocked = self.rule_engine.is_blocked(&domain);

            if is_blocked {
                info!("BLOCKED DNS Request: {}", domain);
                self.stats_engine.record_request(&domain, true);
                return Self::build_blocked_response(payload);
            }

            // Cache is keyed by (domain, qtype): an A-record answer must never be
            // served for an AAAA/TXT query.
            let cache_key = format!("{}|{}", domain, qtype);

            // 3. Check High-Speed DNS Cache
            if let Some(cached_payload) = self.dns_cache.get(&cache_key) {
                debug!("CACHE HIT DNS Request: {}", domain);
                self.stats_engine.record_request(&domain, false);
                // Stamp the cached answer with THIS request's transaction id,
                // otherwise the resolver client rejects the mismatched id.
                return Self::adapt_cached_response(&cached_payload, payload);
            }

            // 4. Forward to Upstream DNS & Cache Result
            info!("ALLOWED DNS Request (Cache Miss): {}", domain);
            self.stats_engine.record_request(&domain, false);
            let response = self.forward_to_upstream(payload);

            if !response.is_empty() {
                self.dns_cache.insert(cache_key, response.clone());
            }

            return response;
        }

        self.forward_to_upstream(payload)
    }

    /// Copy the incoming request's transaction id (first two bytes) into a
    /// cached response so the resolving client accepts it.
    fn adapt_cached_response(cached: &[u8], request: &[u8]) -> Vec<u8> {
        let mut resp = cached.to_vec();
        if resp.len() >= 2 && request.len() >= 2 {
            resp[0] = request[0];
            resp[1] = request[1];
        }
        resp
    }

    fn handle_safesearch_rewrite(domain: &str, payload: &[u8]) -> Option<Vec<u8>> {
        let host = domain.trim_end_matches('.').to_lowercase();

        // Only exact search-frontend hostnames are rewritten. Matching broad
        // substrings (e.g. "google.com") would wrongly capture unrelated services
        // such as mail.google.com / drive.google.com and look-alike domains like
        // google.com.attacker.net, breaking them or enabling spoofing.

        // Google SafeSearch: forcesafesearch.google.com -> 216.239.38.120
        const GOOGLE_SAFE_IP: [u8; 4] = [216, 239, 38, 120];
        const GOOGLE_HOSTS: &[&str] = &[
            "google.com",
            "www.google.com",
            "google.com.vn",
            "www.google.com.vn",
            "google.co.uk",
            "www.google.co.uk",
        ];

        // DuckDuckGo SafeSearch: safe.duckduckgo.com -> 52.142.124.215
        const DDG_SAFE_IP: [u8; 4] = [52, 142, 124, 215];
        const DDG_HOSTS: &[&str] = &["duckduckgo.com", "www.duckduckgo.com"];

        if GOOGLE_HOSTS.contains(&host.as_str()) {
            return Some(Self::build_ip_response(payload, GOOGLE_SAFE_IP));
        }

        if DDG_HOSTS.contains(&host.as_str()) {
            return Some(Self::build_ip_response(payload, DDG_SAFE_IP));
        }

        None
    }

    /// Parse the first DNS question, returning the queried domain and its QTYPE.
    fn extract_question(buffer: &[u8]) -> Option<(String, u16)> {
        if buffer.len() < 12 {
            return None;
        }

        let qdcount = u16::from_be_bytes([buffer[4], buffer[5]]);
        if qdcount == 0 {
            return None;
        }

        let mut offset = 12;
        let mut domain_parts = Vec::new();

        while offset < buffer.len() {
            let len = buffer[offset] as usize;
            if len == 0 {
                break;
            }
            if len > 63 || offset + 1 + len > buffer.len() {
                return None;
            }

            let label = std::str::from_utf8(&buffer[offset + 1..offset + 1 + len]).ok()?;
            domain_parts.push(label);
            offset += 1 + len;
        }

        if domain_parts.is_empty() {
            return None;
        }

        // `offset` points at the zero-length root label; QTYPE follows it.
        let qtype = if offset + 2 < buffer.len() {
            u16::from_be_bytes([buffer[offset + 1], buffer[offset + 2]])
        } else {
            0
        };

        Some((domain_parts.join("."), qtype))
    }

    /// Build an NXDOMAIN reply for a blocked domain. Returning "no such name"
    /// makes clients give up quietly instead of retrying a sinkhole IP.
    fn build_blocked_response(request: &[u8]) -> Vec<u8> {
        let end = match Self::question_end_offset(request) {
            Some(e) => e,
            None => return vec![],
        };

        let mut response = request[..end].to_vec();
        response[2] = 0x81; // QR=1, RD=1
        response[3] = 0x83; // RA=1, RCODE=3 (NXDOMAIN)
        response[6] = 0x00; // ANCOUNT = 0
        response[7] = 0x00;
        response[8] = 0x00; // NSCOUNT = 0
        response[9] = 0x00;
        response[10] = 0x00; // ARCOUNT = 0
        response[11] = 0x00;
        response
    }

    /// Byte offset just past the first DNS question (QNAME + QTYPE + QCLASS).
    fn question_end_offset(buffer: &[u8]) -> Option<usize> {
        if buffer.len() < 12 {
            return None;
        }
        if u16::from_be_bytes([buffer[4], buffer[5]]) == 0 {
            return None;
        }

        let mut offset = 12;
        loop {
            if offset >= buffer.len() {
                return None;
            }
            let len = buffer[offset] as usize;
            if len == 0 {
                offset += 1; // skip the root label terminator
                break;
            }
            if len > 63 || offset + 1 + len > buffer.len() {
                return None;
            }
            offset += 1 + len;
        }

        // QTYPE (2) + QCLASS (2) follow the name.
        if offset + 4 > buffer.len() {
            return None;
        }
        Some(offset + 4)
    }

    fn build_ip_response(request: &[u8], ip: [u8; 4]) -> Vec<u8> {
        if request.len() < 12 {
            return vec![];
        }

        let mut response = request.to_vec();
        response[2] = 0x81;
        response[3] = 0x80;
        response[6] = 0x00;
        response[7] = 0x01;

        response.extend_from_slice(&[0xc0, 0x0c]);
        response.extend_from_slice(&[0x00, 0x01]);
        response.extend_from_slice(&[0x00, 0x01]);
        response.extend_from_slice(&[0x00, 0x00, 0x01, 0x2c]);
        response.extend_from_slice(&[0x00, 0x04]);
        response.extend_from_slice(&ip);

        response
    }

    /// Resolve the configured upstream into a full DoH endpoint URL. A bare
    /// host/IP is wrapped as `https://<host>/dns-query`; an explicit URL is
    /// used unchanged.
    fn doh_endpoint(upstream: &str) -> String {
        if upstream.starts_with("http://") || upstream.starts_with("https://") {
            upstream.to_string()
        } else {
            format!("https://{}/dns-query", upstream)
        }
    }

    /// Forward a DNS query over DNS-over-HTTPS (RFC 8484): the raw DNS wire
    /// message is POSTed with `application/dns-message` and the response body is
    /// the DNS wire answer. Replaces the previous cleartext UDP/53 transport.
    fn forward_to_upstream(&self, payload: &[u8]) -> Vec<u8> {
        use std::io::Read;

        let endpoint = Self::doh_endpoint(&self.upstream_dns);

        let response = ureq::post(&endpoint)
            .set("Content-Type", "application/dns-message")
            .set("Accept", "application/dns-message")
            .timeout(std::time::Duration::from_secs(5))
            .send_bytes(payload);

        match response {
            Ok(resp) => {
                let mut buf = Vec::new();
                if resp.into_reader().take(65_535).read_to_end(&mut buf).is_ok() {
                    buf
                } else {
                    vec![]
                }
            }
            Err(_) => vec![],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dns_domain_extraction() {
        let mock_packet = vec![
            0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x07, b'e', b'x', b'a', b'm', b'p', b'l', b'e',
            0x03, b'c', b'o', b'm', 0x00, 0x00, 0x01, 0x00, 0x01,
        ];

        let question = DnsFilterService::extract_question(&mock_packet);
        assert_eq!(question, Some(("example.com".to_string(), 1)));
    }

    #[test]
    fn test_safesearch_rewrites_search_host_only() {
        // Minimal valid DNS header (>=12 bytes) is enough for response building.
        let query = vec![
            0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ];

        // Search frontends SHOULD be rewritten to the SafeSearch IP.
        assert!(DnsFilterService::handle_safesearch_rewrite("www.google.com", &query).is_some());
        assert!(DnsFilterService::handle_safesearch_rewrite("google.com", &query).is_some());
        assert!(DnsFilterService::handle_safesearch_rewrite("duckduckgo.com", &query).is_some());

        // Non-search Google subdomains must NOT be rewritten (would break Gmail/Drive).
        assert!(DnsFilterService::handle_safesearch_rewrite("mail.google.com", &query).is_none());
        assert!(DnsFilterService::handle_safesearch_rewrite("drive.google.com", &query).is_none());

        // Look-alike / attacker domains must NOT be rewritten.
        assert!(DnsFilterService::handle_safesearch_rewrite("evilgoogle.com", &query).is_none());
        assert!(
            DnsFilterService::handle_safesearch_rewrite("google.com.attacker.net", &query).is_none()
        );
    }

    #[test]
    fn test_extract_question_returns_domain_and_qtype() {
        let packet = vec![
            0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x07, b'e', b'x', b'a', b'm', b'p', b'l', b'e',
            0x03, b'c', b'o', b'm', 0x00, 0x00, 0x01, 0x00, 0x01,
        ];

        let (domain, qtype) = DnsFilterService::extract_question(&packet).unwrap();
        assert_eq!(domain, "example.com");
        assert_eq!(qtype, 1); // A record
    }

    #[test]
    fn test_cached_response_adopts_current_transaction_id() {
        // A cached answer still carries the OLD transaction id 0xAAAA.
        let cached = vec![
            0xAA, 0xAA, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        ];
        // The new incoming request uses transaction id 0x1234.
        let request = vec![
            0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ];

        let served = DnsFilterService::adapt_cached_response(&cached, &request);

        // Transaction id must match the new request, or the client rejects it.
        assert_eq!(served[0], 0x12);
        assert_eq!(served[1], 0x34);
        // The rest of the cached answer must be preserved.
        assert_eq!(served[2], 0x81);
        assert_eq!(served[3], 0x80);
    }

    #[test]
    fn test_doh_endpoint_normalization() {
        // A bare IP/host is turned into a full DoH URL.
        assert_eq!(
            DnsFilterService::doh_endpoint("1.1.1.1"),
            "https://1.1.1.1/dns-query"
        );
        assert_eq!(
            DnsFilterService::doh_endpoint("dns.google"),
            "https://dns.google/dns-query"
        );
        // An explicit URL is used verbatim.
        assert_eq!(
            DnsFilterService::doh_endpoint("https://cloudflare-dns.com/dns-query"),
            "https://cloudflare-dns.com/dns-query"
        );
    }

    #[test]
    fn test_blocked_response_is_nxdomain() {
        let mock_packet = vec![
            0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x03, b'a', b'd', b's', 0x00, 0x00, 0x01, 0x00, 0x01,
        ];

        let response = DnsFilterService::build_blocked_response(&mock_packet);
        assert!(!response.is_empty());
        // Transaction id preserved.
        assert_eq!(&response[0..2], &[0x12, 0x34]);
        // QR bit set (this is a response).
        assert_eq!(response[2] & 0x80, 0x80);
        // RCODE = 3 (NXDOMAIN).
        assert_eq!(response[3] & 0x0f, 0x03);
        // No answer / authority / additional records.
        assert_eq!(u16::from_be_bytes([response[6], response[7]]), 0);
        assert_eq!(u16::from_be_bytes([response[8], response[9]]), 0);
        assert_eq!(u16::from_be_bytes([response[10], response[11]]), 0);
        // The question is echoed back and nothing extra is appended.
        assert_eq!(response.len(), 21);
    }
}
