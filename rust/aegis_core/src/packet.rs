//! Minimal IPv4 + UDP packet parsing/reassembly for the local VPN TUN loop.
//!
//! The TUN interface hands us raw IPv4 packets. To filter DNS we must locate
//! the UDP payload of port-53 datagrams, run it through the DNS engine, and
//! rebuild a valid IPv4/UDP reply (swapped endpoints, corrected lengths and
//! checksums) to write back to the interface.

/// A parsed view over an IPv4 + UDP datagram.
#[derive(Debug, PartialEq, Eq)]
pub struct Ipv4UdpPacket<'a> {
    pub src_ip: [u8; 4],
    pub dst_ip: [u8; 4],
    pub src_port: u16,
    pub dst_port: u16,
    pub payload: &'a [u8],
}

/// Parse an IPv4 packet carrying a UDP datagram. Returns `None` for anything
/// that is not a well-formed IPv4/UDP packet (IPv6, TCP, truncated, options).
pub fn parse_ipv4_udp(packet: &[u8]) -> Option<Ipv4UdpPacket<'_>> {
    if packet.len() < 20 {
        return None;
    }
    // Version must be 4.
    if packet[0] >> 4 != 4 {
        return None;
    }
    let ihl = (packet[0] & 0x0f) as usize * 4;
    if ihl < 20 || packet.len() < ihl + 8 {
        return None;
    }
    // Protocol must be UDP (17).
    if packet[9] != 17 {
        return None;
    }

    let src_ip = [packet[12], packet[13], packet[14], packet[15]];
    let dst_ip = [packet[16], packet[17], packet[18], packet[19]];

    let udp = &packet[ihl..];
    let src_port = u16::from_be_bytes([udp[0], udp[1]]);
    let dst_port = u16::from_be_bytes([udp[2], udp[3]]);
    let udp_len = u16::from_be_bytes([udp[4], udp[5]]) as usize;
    if udp_len < 8 || ihl + udp_len > packet.len() {
        return None;
    }

    let payload = &packet[ihl + 8..ihl + udp_len];

    Some(Ipv4UdpPacket {
        src_ip,
        dst_ip,
        src_port,
        dst_port,
        payload,
    })
}

/// Build an IPv4/UDP reply to `request`, carrying `new_payload` as the UDP
/// payload. Source/destination IPs and ports are swapped and all lengths and
/// checksums are recomputed. Returns `None` if `request` is not IPv4/UDP.
pub fn build_ipv4_udp_response(request: &[u8], new_payload: &[u8]) -> Option<Vec<u8>> {
    let req = parse_ipv4_udp(request)?;

    let udp_len = 8 + new_payload.len();
    let total_len = 20 + udp_len;
    let mut out = vec![0u8; total_len];

    // --- IPv4 header (no options) ---
    out[0] = 0x45; // version 4, IHL 5
    out[2..4].copy_from_slice(&(total_len as u16).to_be_bytes());
    out[8] = 64; // TTL
    out[9] = 17; // UDP
    // Swap source and destination.
    out[12..16].copy_from_slice(&req.dst_ip);
    out[16..20].copy_from_slice(&req.src_ip);
    let ip_csum = internet_checksum(&out[..20]);
    out[10..12].copy_from_slice(&ip_csum.to_be_bytes());

    // --- UDP header ---
    out[20..22].copy_from_slice(&req.dst_port.to_be_bytes());
    out[22..24].copy_from_slice(&req.src_port.to_be_bytes());
    out[24..26].copy_from_slice(&(udp_len as u16).to_be_bytes());
    // UDP checksum is optional over IPv4; 0 means "not computed".
    out[28..].copy_from_slice(new_payload);

    Some(out)
}

/// Standard RFC 1071 internet checksum over `data`.
pub fn internet_checksum(data: &[u8]) -> u16 {
    let mut sum: u32 = 0;
    let mut chunks = data.chunks_exact(2);
    for c in &mut chunks {
        sum += u16::from_be_bytes([c[0], c[1]]) as u32;
    }
    if let [last] = chunks.remainder() {
        sum += (*last as u32) << 8;
    }
    while (sum >> 16) != 0 {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    !(sum as u16)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Assemble an IPv4+UDP+payload packet with a valid IPv4 header checksum.
    fn build_test_packet(
        src_ip: [u8; 4],
        dst_ip: [u8; 4],
        src_port: u16,
        dst_port: u16,
        payload: &[u8],
    ) -> Vec<u8> {
        let total_len = 20 + 8 + payload.len();
        let mut p = vec![0u8; total_len];
        // IPv4 header
        p[0] = 0x45; // version 4, IHL 5
        p[2..4].copy_from_slice(&(total_len as u16).to_be_bytes());
        p[8] = 64; // TTL
        p[9] = 17; // UDP
        p[12..16].copy_from_slice(&src_ip);
        p[16..20].copy_from_slice(&dst_ip);
        let ip_csum = internet_checksum(&p[..20]);
        p[10..12].copy_from_slice(&ip_csum.to_be_bytes());
        // UDP header
        p[20..22].copy_from_slice(&src_port.to_be_bytes());
        p[22..24].copy_from_slice(&dst_port.to_be_bytes());
        p[24..26].copy_from_slice(&((8 + payload.len()) as u16).to_be_bytes());
        // UDP checksum left 0 (optional for IPv4)
        p[28..].copy_from_slice(payload);
        p
    }

    #[test]
    fn test_parse_ipv4_udp_dns_query() {
        let dns = vec![0xAB, 0xCD, 0x01, 0x00];
        let pkt = build_test_packet([10, 0, 0, 2], [1, 1, 1, 1], 40000, 53, &dns);

        let parsed = parse_ipv4_udp(&pkt).unwrap();
        assert_eq!(parsed.src_ip, [10, 0, 0, 2]);
        assert_eq!(parsed.dst_ip, [1, 1, 1, 1]);
        assert_eq!(parsed.src_port, 40000);
        assert_eq!(parsed.dst_port, 53);
        assert_eq!(parsed.payload, dns.as_slice());
    }

    #[test]
    fn test_parse_rejects_tcp_and_ipv6() {
        // TCP (protocol 6) must be rejected.
        let mut tcp = build_test_packet([10, 0, 0, 2], [1, 1, 1, 1], 40000, 53, &[0u8; 4]);
        tcp[9] = 6;
        // checksum now stale but protocol check should reject first anyway
        assert!(parse_ipv4_udp(&tcp).is_none());

        // IPv6 (version 6) must be rejected.
        let ipv6 = vec![0x60u8; 48];
        assert!(parse_ipv4_udp(&ipv6).is_none());
    }

    #[test]
    fn test_build_response_swaps_endpoints_and_has_valid_checksum() {
        let dns_req = vec![0xAB, 0xCD, 0x01, 0x00];
        let req = build_test_packet([10, 0, 0, 2], [1, 1, 1, 1], 40000, 53, &dns_req);

        let dns_resp = vec![0xAB, 0xCD, 0x81, 0x80, 0x00];
        let resp = build_ipv4_udp_response(&req, &dns_resp).unwrap();

        let parsed = parse_ipv4_udp(&resp).unwrap();
        // Endpoints swapped so the reply goes back to the client.
        assert_eq!(parsed.src_ip, [1, 1, 1, 1]);
        assert_eq!(parsed.dst_ip, [10, 0, 0, 2]);
        assert_eq!(parsed.src_port, 53);
        assert_eq!(parsed.dst_port, 40000);
        assert_eq!(parsed.payload, dns_resp.as_slice());

        // A correct IPv4 header checksums to zero when summed including itself.
        assert_eq!(internet_checksum(&resp[..20]), 0);
    }

    #[test]
    fn test_internet_checksum_known_value() {
        // Sum of 0x0000 over empty data is 0 -> ones complement 0xFFFF.
        assert_eq!(internet_checksum(&[]), 0xFFFF);
    }
}
