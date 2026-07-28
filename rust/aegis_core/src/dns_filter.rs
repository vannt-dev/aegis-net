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

    pub fn handle_dns_payload(&self, payload: &[u8], client_addr: SocketAddr) -> Vec<u8> {
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
                return self.forward_to_upstream(payload);
            }
        }

        self.forward_to_upstream(payload)
    }

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

    fn build_blocked_response(request: &[u8]) -> Vec<u8> {
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
        response.extend_from_slice(&[0, 0, 0, 0]);

        response
    }

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dns_domain_extraction() {
        // Mock DNS packet header + QNAME for example.com
        let mut mock_packet = vec![
            0x12, 0x34, // Transaction ID
            0x01, 0x00, // Flags
            0x00, 0x01, // QDCOUNT = 1
            0x00, 0x00, // ANCOUNT = 0
            0x00, 0x00, // NSCOUNT = 0
            0x00, 0x00, // ARCOUNT = 0
            0x07, b'e', b'x', b'a', b'm', b'p', b'l', b'e', // label "example"
            0x03, b'c', b'o', b'm', // label "com"
            0x00, // null terminator
            0x00, 0x01, // QTYPE A
            0x00, 0x01, // QCLASS IN
        ];

        let domain = DnsFilterService::extract_domain_name(&mock_packet);
        assert_eq!(domain, Some("example.com".to_string()));
    }

    #[test]
    fn test_blocked_response_generation() {
        let mock_packet = vec![
            0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x03, b'a', b'd', b's', 0x00, 0x00, 0x01, 0x00, 0x01
        ];

        let response = DnsFilterService::build_blocked_response(&mock_packet);
        assert!(!response.is_empty());
        assert_eq!(response[0], 0x12);
        assert_eq!(response[1], 0x34);
        assert_eq!(response[2], 0x81); // QR=1
        // Last 4 bytes should be 0.0.0.0 IP
        let len = response.len();
        assert_eq!(&response[len - 4..], &[0, 0, 0, 0]);
    }
}
