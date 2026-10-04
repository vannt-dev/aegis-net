//! Minimal IPv4/IPv6 packet parsing and building for the local VPN TUN loop.
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

/// A parsed view over an IPv6 + UDP datagram.
#[derive(Debug, PartialEq, Eq)]
pub struct Ipv6UdpPacket<'a> {
    pub src_ip: [u8; 16],
    pub dst_ip: [u8; 16],
    pub src_port: u16,
    pub dst_port: u16,
    pub payload: &'a [u8],
}

/// Parse an IPv6 packet carrying a UDP datagram.
///
/// Only a bare `IPv6 + UDP` chain is accepted. A packet with extension headers
/// (Hop-by-Hop, Routing, Fragment, ...) has its UDP header further in, so it is
/// rejected rather than parsed at a fixed offset, where option bytes would be
/// read as ports. The TUN carries queries the local resolver sends to our own
/// address, which do not use extension headers in practice.
pub fn parse_ipv6_udp(packet: &[u8]) -> Option<Ipv6UdpPacket<'_>> {
    if packet.len() < 48 {
        return None;
    }
    // Version must be 6.
    if packet[0] >> 4 != 6 {
        return None;
    }
    // Next header must be UDP (17).
    if packet[6] != 17 {
        return None;
    }

    let payload_len = u16::from_be_bytes([packet[4], packet[5]]) as usize;
    if 40 + payload_len > packet.len() || payload_len < 8 {
        return None;
    }

    let mut src_ip = [0u8; 16];
    let mut dst_ip = [0u8; 16];
    src_ip.copy_from_slice(&packet[8..24]);
    dst_ip.copy_from_slice(&packet[24..40]);

    let udp = &packet[40..];
    let src_port = u16::from_be_bytes([udp[0], udp[1]]);
    let dst_port = u16::from_be_bytes([udp[2], udp[3]]);
    let udp_len = u16::from_be_bytes([udp[4], udp[5]]) as usize;

    if udp_len < 8 || 40 + udp_len > packet.len() {
        return None;
    }

    let payload = &packet[48..40 + udp_len];

    Some(Ipv6UdpPacket {
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

/// Build an IPv6/UDP reply to `request`, carrying `new_payload` as the UDP
/// payload. Source/destination IPs and ports are swapped.
pub fn build_ipv6_udp_response(request: &[u8], new_payload: &[u8]) -> Option<Vec<u8>> {
    let req = parse_ipv6_udp(request)?;

    let udp_len = 8 + new_payload.len();
    let total_len = 40 + udp_len;
    let mut out = vec![0u8; total_len];

    // IPv6 header
    out[0] = 0x60; // Version 6
    out[4..6].copy_from_slice(&(udp_len as u16).to_be_bytes());
    out[6] = 17; // Next header: UDP
    out[7] = 64; // Hop limit

    // Swap src and dst IPv6 addresses
    out[8..24].copy_from_slice(&req.dst_ip);
    out[24..40].copy_from_slice(&req.src_ip);

    // UDP header
    out[40..42].copy_from_slice(&req.dst_port.to_be_bytes());
    out[42..44].copy_from_slice(&req.src_port.to_be_bytes());
    out[44..46].copy_from_slice(&(udp_len as u16).to_be_bytes());
    out[48..].copy_from_slice(new_payload);

    // Calculate IPv6 UDP checksum
    let mut pseudo = Vec::with_capacity(40 + udp_len);
    pseudo.extend_from_slice(&req.dst_ip);
    pseudo.extend_from_slice(&req.src_ip);
    pseudo.extend_from_slice(&(udp_len as u32).to_be_bytes());
    pseudo.extend_from_slice(&[0, 0, 0, 17]);
    pseudo.extend_from_slice(&out[40..]);

    let csum = internet_checksum(&pseudo);
    let csum_bytes = if csum == 0 { 0xFFFFu16 } else { csum }.to_be_bytes();
    out[46..48].copy_from_slice(&csum_bytes);

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

pub const TCP_FIN: u8 = 0x01;
pub const TCP_SYN: u8 = 0x02;
pub const TCP_RST: u8 = 0x04;
pub const TCP_ACK: u8 = 0x10;

const PROTO_ICMP: u8 = 1;
const PROTO_TCP: u8 = 6;
const PROTO_UDP: u8 = 17;
const PROTO_ICMPV6: u8 = 58;

/// The TCP fields a reset needs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TcpHeader {
    pub src_port: u16,
    pub dst_port: u16,
    pub seq: u32,
    pub ack: u32,
    pub flags: u8,
    pub payload_len: u32,
}

fn read_tcp(segment: &[u8]) -> Option<TcpHeader> {
    if segment.len() < 20 {
        return None;
    }
    let data_offset = (segment[12] >> 4) as usize * 4;
    if data_offset < 20 || data_offset > segment.len() {
        return None;
    }
    Some(TcpHeader {
        src_port: u16::from_be_bytes([segment[0], segment[1]]),
        dst_port: u16::from_be_bytes([segment[2], segment[3]]),
        seq: u32::from_be_bytes([segment[4], segment[5], segment[6], segment[7]]),
        ack: u32::from_be_bytes([segment[8], segment[9], segment[10], segment[11]]),
        flags: segment[13],
        payload_len: (segment.len() - data_offset) as u32,
    })
}

/// An unfragmented IPv4 packet carrying TCP. Later fragments carry no TCP
/// header, so they are refused rather than misread.
pub fn parse_ipv4_tcp(packet: &[u8]) -> Option<([u8; 4], [u8; 4], TcpHeader)> {
    if packet.len() < 20 || packet[0] >> 4 != 4 || packet[9] != PROTO_TCP {
        return None;
    }
    let fragment_offset = u16::from_be_bytes([packet[6] & 0x1f, packet[7]]);
    if fragment_offset != 0 {
        return None;
    }
    let ihl = (packet[0] & 0x0f) as usize * 4;
    let total = (u16::from_be_bytes([packet[2], packet[3]]) as usize).min(packet.len());
    if ihl < 20 || total < ihl + 20 {
        return None;
    }
    let tcp = read_tcp(&packet[ihl..total])?;
    Some((
        [packet[12], packet[13], packet[14], packet[15]],
        [packet[16], packet[17], packet[18], packet[19]],
        tcp,
    ))
}

/// An IPv6 packet whose next header is TCP (no extension headers).
pub fn parse_ipv6_tcp(packet: &[u8]) -> Option<([u8; 16], [u8; 16], TcpHeader)> {
    if packet.len() < 60 || packet[0] >> 4 != 6 || packet[6] != PROTO_TCP {
        return None;
    }
    let payload_len = u16::from_be_bytes([packet[4], packet[5]]) as usize;
    let end = (40 + payload_len).min(packet.len());
    let tcp = read_tcp(&packet[40..end])?;
    let mut src = [0u8; 16];
    let mut dst = [0u8; 16];
    src.copy_from_slice(&packet[8..24]);
    dst.copy_from_slice(&packet[24..40]);
    Some((src, dst, tcp))
}

/// Sequence, acknowledgement and flags of the reset answering `h` (RFC 793,
/// "Reset Generation"), or None when `h` is itself a reset.
fn reset_for(h: &TcpHeader) -> Option<(u32, u32, u8)> {
    if h.flags & TCP_RST != 0 {
        return None;
    }
    if h.flags & TCP_ACK != 0 {
        return Some((h.ack, 0, TCP_RST));
    }
    let mut consumed = h.payload_len;
    if h.flags & TCP_SYN != 0 {
        consumed += 1;
    }
    if h.flags & TCP_FIN != 0 {
        consumed += 1;
    }
    Some((0, h.seq.wrapping_add(consumed), TCP_RST | TCP_ACK))
}

fn tcp_segment(h: &TcpHeader, seq: u32, ack: u32, flags: u8) -> [u8; 20] {
    let mut s = [0u8; 20];
    s[0..2].copy_from_slice(&h.dst_port.to_be_bytes());
    s[2..4].copy_from_slice(&h.src_port.to_be_bytes());
    s[4..8].copy_from_slice(&seq.to_be_bytes());
    s[8..12].copy_from_slice(&ack.to_be_bytes());
    s[12] = 5 << 4;
    s[13] = flags;
    s
}

fn ipv4_header(total_len: usize, proto: u8, src: [u8; 4], dst: [u8; 4]) -> [u8; 20] {
    let mut h = [0u8; 20];
    h[0] = 0x45;
    h[2..4].copy_from_slice(&(total_len as u16).to_be_bytes());
    h[8] = 64;
    h[9] = proto;
    h[12..16].copy_from_slice(&src);
    h[16..20].copy_from_slice(&dst);
    let csum = internet_checksum(&h);
    h[10..12].copy_from_slice(&csum.to_be_bytes());
    h
}

fn ipv6_header(payload_len: usize, next: u8, src: [u8; 16], dst: [u8; 16]) -> [u8; 40] {
    let mut h = [0u8; 40];
    h[0] = 0x60;
    h[4..6].copy_from_slice(&(payload_len as u16).to_be_bytes());
    h[6] = next;
    h[7] = 64;
    h[8..24].copy_from_slice(&src);
    h[24..40].copy_from_slice(&dst);
    h
}

fn pseudo_checksum_v4(src: [u8; 4], dst: [u8; 4], proto: u8, segment: &[u8]) -> u16 {
    let mut pseudo = Vec::with_capacity(12 + segment.len());
    pseudo.extend_from_slice(&src);
    pseudo.extend_from_slice(&dst);
    pseudo.extend_from_slice(&[0, proto]);
    pseudo.extend_from_slice(&(segment.len() as u16).to_be_bytes());
    pseudo.extend_from_slice(segment);
    internet_checksum(&pseudo)
}

fn pseudo_checksum_v6(src: [u8; 16], dst: [u8; 16], next: u8, segment: &[u8]) -> u16 {
    let mut pseudo = Vec::with_capacity(40 + segment.len());
    pseudo.extend_from_slice(&src);
    pseudo.extend_from_slice(&dst);
    pseudo.extend_from_slice(&(segment.len() as u32).to_be_bytes());
    pseudo.extend_from_slice(&[0, 0, 0, next]);
    pseudo.extend_from_slice(segment);
    internet_checksum(&pseudo)
}

/// A reset refusing an IPv4 TCP segment, sent as if by its destination.
pub fn build_tcp_reset_v4(request: &[u8]) -> Option<Vec<u8>> {
    let (src, dst, h) = parse_ipv4_tcp(request)?;
    let (seq, ack, flags) = reset_for(&h)?;
    let mut tcp = tcp_segment(&h, seq, ack, flags);
    let csum = pseudo_checksum_v4(dst, src, PROTO_TCP, &tcp);
    tcp[16..18].copy_from_slice(&csum.to_be_bytes());
    let mut out = ipv4_header(40, PROTO_TCP, dst, src).to_vec();
    out.extend_from_slice(&tcp);
    Some(out)
}

/// A reset refusing an IPv6 TCP segment, sent as if by its destination.
pub fn build_tcp_reset_v6(request: &[u8]) -> Option<Vec<u8>> {
    let (src, dst, h) = parse_ipv6_tcp(request)?;
    let (seq, ack, flags) = reset_for(&h)?;
    let mut tcp = tcp_segment(&h, seq, ack, flags);
    let csum = pseudo_checksum_v6(dst, src, PROTO_TCP, &tcp);
    tcp[16..18].copy_from_slice(&csum.to_be_bytes());
    let mut out = ipv6_header(20, PROTO_TCP, dst, src).to_vec();
    out.extend_from_slice(&tcp);
    Some(out)
}

/// ICMP "port unreachable" for an IPv4 UDP datagram, quoting its IP header
/// and the first 8 bytes after it (RFC 792).
pub fn build_udp_port_unreachable_v4(request: &[u8]) -> Option<Vec<u8>> {
    let udp = parse_ipv4_udp(request)?;
    let ihl = (request[0] & 0x0f) as usize * 4;
    let quote = &request[..(ihl + 8).min(request.len())];
    let mut icmp = vec![3u8, 3, 0, 0, 0, 0, 0, 0];
    icmp.extend_from_slice(quote);
    let csum = internet_checksum(&icmp);
    icmp[2..4].copy_from_slice(&csum.to_be_bytes());
    let mut out = ipv4_header(20 + icmp.len(), PROTO_ICMP, udp.dst_ip, udp.src_ip).to_vec();
    out.extend_from_slice(&icmp);
    Some(out)
}

/// ICMPv6 "port unreachable" for an IPv6 UDP datagram, quoting as much of it
/// as fits in the minimum IPv6 MTU (RFC 4443).
pub fn build_udp_port_unreachable_v6(request: &[u8]) -> Option<Vec<u8>> {
    let udp = parse_ipv6_udp(request)?;
    let quote = &request[..request.len().min(1280 - 48)];
    let mut icmp = vec![1u8, 4, 0, 0, 0, 0, 0, 0];
    icmp.extend_from_slice(quote);
    let csum = pseudo_checksum_v6(udp.dst_ip, udp.src_ip, PROTO_ICMPV6, &icmp);
    icmp[2..4].copy_from_slice(&csum.to_be_bytes());
    let mut out = ipv6_header(icmp.len(), PROTO_ICMPV6, udp.dst_ip, udp.src_ip).to_vec();
    out.extend_from_slice(&icmp);
    Some(out)
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

    /// Assemble an IPv6+UDP+payload packet.
    fn build_test_packet_v6(
        src_ip: [u8; 16],
        dst_ip: [u8; 16],
        src_port: u16,
        dst_port: u16,
        payload: &[u8],
    ) -> Vec<u8> {
        let udp_len = 8 + payload.len();
        let mut p = vec![0u8; 40 + udp_len];
        p[0] = 0x60; // version 6
        p[4..6].copy_from_slice(&(udp_len as u16).to_be_bytes());
        p[6] = 17; // next header: UDP
        p[7] = 64; // hop limit
        p[8..24].copy_from_slice(&src_ip);
        p[24..40].copy_from_slice(&dst_ip);
        p[40..42].copy_from_slice(&src_port.to_be_bytes());
        p[42..44].copy_from_slice(&dst_port.to_be_bytes());
        p[44..46].copy_from_slice(&(udp_len as u16).to_be_bytes());
        p[48..].copy_from_slice(payload);
        p
    }

    const TUN_V6: [u8; 16] = [0xfd, 0x00, 0xae, 0xed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3];
    const CLIENT_V6: [u8; 16] = [0xfd, 0x00, 0xae, 0xed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2];

    #[test]
    fn test_parse_ipv6_udp_dns_query() {
        let dns = vec![0xAB, 0xCD, 0x01, 0x00];
        let pkt = build_test_packet_v6(CLIENT_V6, TUN_V6, 40000, 53, &dns);

        let parsed = parse_ipv6_udp(&pkt).unwrap();
        assert_eq!(parsed.src_ip, CLIENT_V6);
        assert_eq!(parsed.dst_ip, TUN_V6);
        assert_eq!(parsed.src_port, 40000);
        assert_eq!(parsed.dst_port, 53);
        assert_eq!(parsed.payload, dns.as_slice());
    }

    #[test]
    fn test_ipv6_parser_rejects_other_protocols_and_ipv4() {
        // TCP (next header 6) is not ours to answer.
        let mut tcp = build_test_packet_v6(CLIENT_V6, TUN_V6, 40000, 53, &[0u8; 4]);
        tcp[6] = 6;
        assert!(parse_ipv6_udp(&tcp).is_none());

        // An IPv4 packet must not be read as IPv6.
        let v4 = build_test_packet([10, 0, 0, 2], [10, 0, 0, 3], 40000, 53, &[0u8; 16]);
        assert!(parse_ipv6_udp(&v4).is_none());

        // A truncated header must not panic on the fixed-offset slices.
        assert!(parse_ipv6_udp(&[0x60u8; 20]).is_none());

        // A payload length field that runs past the buffer is a lie.
        let mut short = build_test_packet_v6(CLIENT_V6, TUN_V6, 40000, 53, &[0u8; 4]);
        short[5] = 0xff;
        assert!(parse_ipv6_udp(&short).is_none());
    }

    #[test]
    fn test_ipv6_extension_headers_are_not_mistaken_for_udp() {
        // A Hop-by-Hop header (next header 0) puts the UDP header further in;
        // reading offset 40 as UDP would invent a port out of option bytes.
        let mut pkt = build_test_packet_v6(CLIENT_V6, TUN_V6, 40000, 53, &[0u8; 4]);
        pkt[6] = 0;
        assert!(parse_ipv6_udp(&pkt).is_none());
    }

    #[test]
    fn test_build_ipv6_response_swaps_endpoints_and_has_valid_checksum() {
        let req = build_test_packet_v6(CLIENT_V6, TUN_V6, 40000, 53, &[0xAB, 0xCD, 0x01, 0x00]);

        let dns_resp = vec![0xAB, 0xCD, 0x81, 0x80, 0x00];
        let resp = build_ipv6_udp_response(&req, &dns_resp).unwrap();

        let parsed = parse_ipv6_udp(&resp).unwrap();
        assert_eq!(parsed.src_ip, TUN_V6, "reply comes from the resolver");
        assert_eq!(parsed.dst_ip, CLIENT_V6);
        assert_eq!(parsed.src_port, 53);
        assert_eq!(parsed.dst_port, 40000);
        assert_eq!(parsed.payload, dns_resp.as_slice());

        // UDP checksum is mandatory over IPv6, so verifying the pseudo-header
        // sum over the received packet must come out to zero.
        let udp_len = 8 + dns_resp.len();
        let mut pseudo = Vec::new();
        pseudo.extend_from_slice(&resp[8..40]); // src + dst
        pseudo.extend_from_slice(&(udp_len as u32).to_be_bytes());
        pseudo.extend_from_slice(&[0, 0, 0, 17]);
        pseudo.extend_from_slice(&resp[40..]);
        assert_eq!(internet_checksum(&pseudo), 0, "UDP checksum must verify");
    }

    #[test]
    fn test_ipv4_parser_rejects_tcp_and_ipv6() {
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

    fn tcp_v4(flags: u8, seq: u32, ack: u32, payload: &[u8]) -> Vec<u8> {
        let total = 20 + 20 + payload.len();
        let mut p = vec![0u8; total];
        p[0] = 0x45;
        p[2..4].copy_from_slice(&(total as u16).to_be_bytes());
        p[8] = 64;
        p[9] = 6;
        p[12..16].copy_from_slice(&[10, 0, 0, 2]);
        p[16..20].copy_from_slice(&[8, 8, 8, 8]);
        p[20..22].copy_from_slice(&40000u16.to_be_bytes());
        p[22..24].copy_from_slice(&853u16.to_be_bytes());
        p[24..28].copy_from_slice(&seq.to_be_bytes());
        p[28..32].copy_from_slice(&ack.to_be_bytes());
        p[32] = 5 << 4;
        p[33] = flags;
        p[40..].copy_from_slice(payload);
        p
    }

    fn tcp_v6(flags: u8, seq: u32) -> Vec<u8> {
        let mut p = vec![0u8; 40 + 20];
        p[0] = 0x60;
        p[4..6].copy_from_slice(&20u16.to_be_bytes());
        p[6] = 6;
        p[7] = 64;
        p[8] = 0xfd;
        p[23] = 2;
        p[24..40].copy_from_slice(&[
            0x20, 0x01, 0x48, 0x60, 0x48, 0x60, 0, 0, 0, 0, 0, 0, 0, 0, 0x88, 0x88,
        ]);
        p[40..42].copy_from_slice(&40001u16.to_be_bytes());
        p[42..44].copy_from_slice(&443u16.to_be_bytes());
        p[44..48].copy_from_slice(&seq.to_be_bytes());
        p[52] = 5 << 4;
        p[53] = flags;
        p
    }

    fn udp_v4(dst_port: u16) -> Vec<u8> {
        let payload = [1u8, 2, 3, 4];
        let total = 20 + 8 + payload.len();
        let mut p = vec![0u8; total];
        p[0] = 0x45;
        p[2..4].copy_from_slice(&(total as u16).to_be_bytes());
        p[8] = 64;
        p[9] = 17;
        p[12..16].copy_from_slice(&[10, 0, 0, 2]);
        p[16..20].copy_from_slice(&[1, 1, 1, 1]);
        p[20..22].copy_from_slice(&40002u16.to_be_bytes());
        p[22..24].copy_from_slice(&dst_port.to_be_bytes());
        p[24..26].copy_from_slice(&((8 + payload.len()) as u16).to_be_bytes());
        p[28..].copy_from_slice(&payload);
        p
    }

    fn udp_v6(dst_port: u16) -> Vec<u8> {
        let mut p = vec![0u8; 40 + 8 + 4];
        p[0] = 0x60;
        p[4..6].copy_from_slice(&12u16.to_be_bytes());
        p[6] = 17;
        p[7] = 64;
        p[8] = 0xfd;
        p[23] = 2;
        p[24..40].copy_from_slice(&[
            0x26, 0x06, 0x47, 0, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x11, 0x11,
        ]);
        p[40..42].copy_from_slice(&40003u16.to_be_bytes());
        p[42..44].copy_from_slice(&dst_port.to_be_bytes());
        p[44..46].copy_from_slice(&12u16.to_be_bytes());
        p
    }

    /// One's-complement sum over the pseudo-header and segment must fold to 0.
    fn checksum_ok_v4(ip: &[u8], proto: u8) -> bool {
        let seg = &ip[20..];
        let mut pseudo = Vec::new();
        pseudo.extend_from_slice(&ip[12..20]);
        pseudo.extend_from_slice(&[0, proto]);
        pseudo.extend_from_slice(&(seg.len() as u16).to_be_bytes());
        pseudo.extend_from_slice(seg);
        internet_checksum(&pseudo) == 0
    }

    fn checksum_ok_v6(ip: &[u8], proto: u8) -> bool {
        let seg = &ip[40..];
        let mut pseudo = Vec::new();
        pseudo.extend_from_slice(&ip[8..40]);
        pseudo.extend_from_slice(&(seg.len() as u32).to_be_bytes());
        pseudo.extend_from_slice(&[0, 0, 0, proto]);
        pseudo.extend_from_slice(seg);
        internet_checksum(&pseudo) == 0
    }

    #[test]
    fn a_syn_gets_rst_ack_for_seq_plus_one() {
        let reply = build_tcp_reset_v4(&tcp_v4(TCP_SYN, 1000, 0, &[])).expect("reset");
        let (src, dst, h) = parse_ipv4_tcp(&reply).expect("tcp");
        assert_eq!(src, [8, 8, 8, 8]);
        assert_eq!(dst, [10, 0, 0, 2]);
        assert_eq!((h.src_port, h.dst_port), (853, 40000));
        assert_eq!(h.flags, TCP_RST | TCP_ACK);
        assert_eq!((h.seq, h.ack), (0, 1001));
        assert_eq!(internet_checksum(&reply[..20]), 0);
        assert!(checksum_ok_v4(&reply, 6));
    }

    #[test]
    fn a_segment_with_ack_gets_a_bare_rst_at_that_ack() {
        let reply = build_tcp_reset_v4(&tcp_v4(TCP_ACK, 5, 777, b"hello")).expect("reset");
        let (_, _, h) = parse_ipv4_tcp(&reply).expect("tcp");
        assert_eq!(h.flags, TCP_RST);
        assert_eq!(h.seq, 777);
    }

    #[test]
    fn a_data_segment_without_ack_is_acked_past_its_payload() {
        let reply = build_tcp_reset_v4(&tcp_v4(TCP_FIN, 10, 0, b"abc")).expect("reset");
        let (_, _, h) = parse_ipv4_tcp(&reply).expect("tcp");
        assert_eq!(h.ack, 10 + 3 + 1);
    }

    #[test]
    fn a_reset_is_never_answered() {
        assert!(build_tcp_reset_v4(&tcp_v4(TCP_RST, 1, 0, &[])).is_none());
        assert!(build_tcp_reset_v4(&tcp_v4(TCP_RST | TCP_ACK, 1, 2, &[])).is_none());
        assert!(build_tcp_reset_v6(&tcp_v6(TCP_RST, 1)).is_none());
    }

    #[test]
    fn ipv6_syn_gets_a_valid_reset() {
        let reply = build_tcp_reset_v6(&tcp_v6(TCP_SYN, 41)).expect("reset");
        let (src, _, h) = parse_ipv6_tcp(&reply).expect("tcp");
        assert_eq!(src[0..2], [0x20, 0x01]);
        assert_eq!(h.flags, TCP_RST | TCP_ACK);
        assert_eq!(h.ack, 42);
        assert!(checksum_ok_v6(&reply, 6));
    }

    #[test]
    fn non_tcp_and_fragments_get_no_reset() {
        assert!(build_tcp_reset_v4(&udp_v4(443)).is_none());
        let mut fragment = tcp_v4(TCP_SYN, 1, 0, &[]);
        fragment[7] = 1; // non-zero fragment offset
        assert!(build_tcp_reset_v4(&fragment).is_none());
        assert!(build_tcp_reset_v4(&tcp_v4(TCP_SYN, 1, 0, &[])[..30]).is_none());
    }

    #[test]
    fn udp_to_another_port_gets_icmp_port_unreachable() {
        let request = udp_v4(443);
        let reply = build_udp_port_unreachable_v4(&request).expect("icmp");
        assert_eq!(reply[9], 1); // ICMP
        assert_eq!(&reply[12..16], &[1, 1, 1, 1]);
        assert_eq!(&reply[16..20], &[10, 0, 0, 2]);
        assert_eq!((reply[20], reply[21]), (3, 3));
        assert_eq!(internet_checksum(&reply[..20]), 0);
        assert_eq!(internet_checksum(&reply[20..]), 0);
        // Quotes the original IP header plus the first 8 bytes after it.
        assert_eq!(&reply[28..], &request[..28]);
    }

    #[test]
    fn ipv6_udp_gets_icmpv6_port_unreachable() {
        let request = udp_v6(853);
        let reply = build_udp_port_unreachable_v6(&request).expect("icmpv6");
        assert_eq!(reply[6], 58);
        assert_eq!((reply[40], reply[41]), (1, 4));
        assert_eq!(&reply[48..], &request[..]);
        assert!(checksum_ok_v6(&reply, 58));
    }

    #[test]
    fn only_udp_gets_port_unreachable() {
        assert!(build_udp_port_unreachable_v4(&tcp_v4(TCP_SYN, 1, 0, &[])).is_none());
        assert!(build_udp_port_unreachable_v6(&tcp_v6(TCP_SYN, 1)).is_none());
    }
}
