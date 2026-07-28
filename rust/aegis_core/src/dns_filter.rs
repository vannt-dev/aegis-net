use std::net::{SocketAddr, UdpSocket};
use std::sync::Arc;
use log::{info, warn, error};
use crate::rule_engine::RuleEngine;
use crate::statistics::StatisticsEngine;

pub struct DnsFilterService {
    rule_engine: Arc<RuleEngine>,
    stats_engine: Arc<StatisticsEngine>,
    upstream_dns: String,
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
            upstream_dns,
        }
    }

    /// Process a DNS UDP packet payload
    pub fn handle_dns_payload(&self, payload: &[u8], client_addr: SocketAddr) -> Vec<u8> {
        // Extract query domain from raw DNS packet (RFC 1035)
        let domain_opt = Self::extract_domain_name(payload);

        if let Some(domain) = domain_opt {
            let is_blocked = self.rule_engine.is_blocked(&domain);

            if is_blocked {
                info!("BLOCKED DNS Request: {}", domain);
                self.stats_engine.record_request(&domain, true);
                return Self::build_blocked_response(payload);
            } else {
                info!("ALLOWED DNS Request: {}", domain);
                self.stats_engine.record_request(&domain, false);
                // Forward query to upstream DNS
                return self.forward_to_upstream(payload);
            }
        }

        // Fallback forward if unparseable
        self.forward_to_upstream(payload)
    }

    /// Extract QNAME domain from raw DNS query bytes
    fn extract_domain_name(buffer: &[u8]) -> Option<String> {
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
            None
        } else {
            Some(domain_parts.join("."))
        }
    }

    /// Build a DNS response packet pointing A records to 0.0.0.0 (Sinkhole)
    fn build_blocked_response(request: &[u8]) -> Vec<u8> {
        if request.len() < 12 {
            return vec![];
        }

        let mut response = request.to_vec();
        // Set Flags: QR=1 (Response), RCODE=0 (NoError)
        response[2] = 0x81;
        response[3] = 0x80;
        // ANCOUNT = 1
        response[6] = 0x00;
        response[7] = 0x01;

        // Append 0.0.0.0 A Record Answer
        // Name pointer (0xc00c) points to QNAME in header offset 12
        response.extend_from_slice(&[0xc0, 0x0c]); // Name offset
        response.extend_from_slice(&[0x00, 0x01]); // Type A
        response.extend_from_slice(&[0x00, 0x01]); // Class IN
        response.extend_from_slice(&[0x00, 0x00, 0x01, 0x2c]); // TTL (300s)
        response.extend_from_slice(&[0x00, 0x04]); // Data length = 4 bytes
        response.extend_from_slice(&[0, 0, 0, 0]); // IP 0.0.0.0

        response
    }

    /// Forward request to public upstream DNS server
    fn forward_to_upstream(&self, payload: &[u8]) -> Vec<u8> {
        let socket = match UdpSocket::bind("0.0.0.0:0") {
            Ok(s) => s,
            Err(_) => return vec![],
        };

        socket.set_read_timeout(Some(std::time::Duration::from_secs(3))).ok();
        
        let upstream_target = format!("{}:53", self.upstream_dns);
        if socket.send_to(payload, &upstream_target).is_err() {
            return vec![];
        }

        let mut buf = [0u8; 512];
        match socket.recv_from(&mut buf) {
            Ok((amt, _)) => buf[..amt].to_vec(),
            Err(_) => vec![],
        }
    }
}
