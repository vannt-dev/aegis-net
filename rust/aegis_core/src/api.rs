use crate::dns_filter::DnsFilterService;
use crate::rule_engine::{RuleCategory, RuleEngine};
use crate::shared_state;
use crate::statistics::StatisticsEngine;
use lazy_static::lazy_static;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::path::Path;
use std::sync::Arc;

lazy_static! {
    static ref RULE_ENGINE: Arc<RuleEngine> = Arc::new(RuleEngine::new());
    static ref STATS_ENGINE: Arc<StatisticsEngine> = Arc::new(StatisticsEngine::new(1000));
    // IP-literal DoH endpoint on purpose: the default needs no DNS lookup at
    // all, so it works before anything else does. (A host-name upstream
    // used to recurse back into our own captured resolver and deadlock; the
    // Android service now keeps the app out of its own tunnel to stop that.)
    // Cloudflare's certificate carries a 1.1.1.1 IP SAN, so TLS verification
    // still succeeds without any prior DNS lookup.
    static ref DNS_FILTER: Arc<DnsFilterService> = Arc::new(DnsFilterService::new(
        RULE_ENGINE.clone(),
        STATS_ENGINE.clone(),
        "https://1.1.1.1/dns-query".to_string()
    ));
}

/// Initialize Aegis Core Engine
#[no_mangle]
pub extern "C" fn aegis_init() -> c_int {
    // A second Flutter engine in the same process (activity reopened while the
    // VPN service kept the process alive) calls this again; init_from_env
    // would abort the process, tunnel included.
    let _ = env_logger::try_init_from_env(env_logger::Env::default().default_filter_or("info"));
    log::info!("Aegis Core Engine Initialized");
    1
}

/// Enable or disable a rule category (0: Ads, 1: Trackers, 2: Malware, 3: Adult)
#[no_mangle]
pub extern "C" fn aegis_set_category(category_id: c_int, enabled: c_int) {
    let cat = match category_id {
        0 => RuleCategory::Ads,
        1 => RuleCategory::Trackers,
        2 => RuleCategory::Malware,
        3 => RuleCategory::Adult,
        _ => return,
    };
    RULE_ENGINE.set_category_enabled(cat, enabled != 0);
    // The rule set just changed; answers cached under the old one must not
    // outlive it.
    DNS_FILTER.clear_cache();
}

/// Set the upstream DoH target used to resolve cache-miss queries. Accepts a
/// bare host/IP or a full `https://.../dns-query` URL.
#[no_mangle]
pub extern "C" fn aegis_set_upstream_dns(upstream_ptr: *const c_char) {
    if upstream_ptr.is_null() {
        return;
    }
    if let Ok(upstream) = unsafe { CStr::from_ptr(upstream_ptr) }.to_str() {
        DNS_FILTER.set_upstream_dns(upstream);
    }
}

/// Load filter rules text into engine
#[no_mangle]
pub extern "C" fn aegis_load_rules(rules_text_ptr: *const c_char, category_id: c_int) -> u32 {
    if rules_text_ptr.is_null() {
        return 0;
    }
    let cat = match category_id {
        0 => RuleCategory::Ads,
        1 => RuleCategory::Trackers,
        2 => RuleCategory::Malware,
        3 => RuleCategory::Adult,
        _ => RuleCategory::Ads,
    };
    let c_str = unsafe { CStr::from_ptr(rules_text_ptr) };
    if let Ok(rules_str) = c_str.to_str() {
        RULE_ENGINE.load_rules_text(rules_str, cat) as u32
    } else {
        0
    }
}

/// Borrow a C string as a filesystem path, or `None` when it is null or not
/// valid UTF-8.
fn path_from_ptr(path_ptr: *const c_char) -> Option<&'static Path> {
    if path_ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(path_ptr) }
        .to_str()
        .ok()
        .map(Path::new)
}

/// Write the engine's user settings to `path` for the other process to pick up.
/// Returns 0 on success, or a negative [`shared_state::SnapshotError`] code.
///
/// iOS only: the app calls this after a rule change so the PacketTunnel
/// extension, which holds a separate copy of the engine, can adopt it.
#[no_mangle]
pub extern "C" fn aegis_export_settings(path_ptr: *const c_char) -> c_int {
    match path_from_ptr(path_ptr) {
        Some(path) => match shared_state::export_settings(&RULE_ENGINE, &DNS_FILTER, path) {
            Ok(()) => 0,
            Err(err) => err.code(),
        },
        None => shared_state::SnapshotError::Io.code(),
    }
}

/// Adopt the settings snapshot at `path`. Entries missing from the snapshot are
/// removed, so the reader ends up matching the writer exactly.
#[no_mangle]
pub extern "C" fn aegis_import_settings(path_ptr: *const c_char) -> c_int {
    match path_from_ptr(path_ptr) {
        Some(path) => match shared_state::import_settings(&RULE_ENGINE, &DNS_FILTER, path) {
            Ok(()) => 0,
            Err(err) => err.code(),
        },
        None => shared_state::SnapshotError::Io.code(),
    }
}

/// Load a filter list from disk instead of from a C string. Downloaded lists
/// run to hundreds of thousands of lines; passing a path avoids marshalling
/// megabytes across the FFI boundary. Returns the number of rules added.
#[no_mangle]
pub extern "C" fn aegis_load_rules_file(path_ptr: *const c_char, category_id: c_int) -> u32 {
    let cat = match category_id {
        0 => RuleCategory::Ads,
        1 => RuleCategory::Trackers,
        2 => RuleCategory::Malware,
        3 => RuleCategory::Adult,
        _ => RuleCategory::Ads,
    };
    match path_from_ptr(path_ptr) {
        Some(path) => shared_state::load_rules_file(&RULE_ENGINE, path, cat).unwrap_or(0) as u32,
        None => 0,
    }
}

/// Publish the counters this process has accumulated. Called by the iOS
/// extension, which is the only side that sees real DNS traffic.
#[no_mangle]
pub extern "C" fn aegis_export_stats(path_ptr: *const c_char) -> c_int {
    match path_from_ptr(path_ptr) {
        Some(path) => match shared_state::export_stats(&STATS_ENGINE, path) {
            Ok(()) => 0,
            Err(err) => err.code(),
        },
        None => shared_state::SnapshotError::Io.code(),
    }
}

/// Adopt counters published by the other process, so `aegis_get_stats_json`
/// reports what the tunnel actually did rather than this process's own totals.
#[no_mangle]
pub extern "C" fn aegis_import_stats(path_ptr: *const c_char) -> c_int {
    match path_from_ptr(path_ptr) {
        Some(path) => match shared_state::import_stats(&STATS_ENGINE, path) {
            Ok(()) => 0,
            Err(err) => err.code(),
        },
        None => shared_state::SnapshotError::Io.code(),
    }
}

/// Add domain to Whitelist
#[no_mangle]
pub extern "C" fn aegis_add_whitelist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() {
        return;
    }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.add_whitelist(domain);
    }
}

/// Add domain to Blacklist
#[no_mangle]
pub extern "C" fn aegis_add_blacklist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() {
        return;
    }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.add_blacklist(domain);
    }
}

/// Remove domain from Whitelist
#[no_mangle]
pub extern "C" fn aegis_remove_whitelist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() {
        return;
    }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.remove_whitelist(domain);
    }
}

/// Remove domain from Blacklist
#[no_mangle]
pub extern "C" fn aegis_remove_blacklist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() {
        return;
    }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.remove_blacklist(domain);
    }
}

/// Drop rules that came from downloaded filter lists, keeping the user's own
/// allow/deny lists and host overrides. Call before re-loading the lists so an
/// unsubscribed blocklist actually stops blocking.
#[no_mangle]
pub extern "C" fn aegis_clear_downloaded_rules() {
    RULE_ENGINE.clear_downloaded_rules();
}

/// Add custom host mapping (e.g. domain -> IP)
#[no_mangle]
pub extern "C" fn aegis_add_custom_host(domain_ptr: *const c_char, ip_ptr: *const c_char) {
    if domain_ptr.is_null() || ip_ptr.is_null() {
        return;
    }
    if let (Ok(domain), Ok(ip)) = (
        unsafe { CStr::from_ptr(domain_ptr) }.to_str(),
        unsafe { CStr::from_ptr(ip_ptr) }.to_str(),
    ) {
        RULE_ENGINE.add_custom_host(domain, ip);
    }
}

/// Remove custom host mapping
#[no_mangle]
pub extern "C" fn aegis_remove_custom_host(domain_ptr: *const c_char) {
    if domain_ptr.is_null() {
        return;
    }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.remove_custom_host(domain);
    }
}

/// Check if domain is blocked
#[no_mangle]
pub extern "C" fn aegis_is_domain_blocked(domain_ptr: *const c_char) -> c_int {
    if domain_ptr.is_null() {
        return 0;
    }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        if RULE_ENGINE.is_blocked(domain) {
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Process a DNS raw packet payload
#[no_mangle]
pub extern "C" fn aegis_handle_dns_packet(
    in_buf: *const u8,
    in_len: usize,
    out_buf: *mut u8,
    out_max_len: usize,
) -> usize {
    if in_buf.is_null() || out_buf.is_null() || in_len == 0 {
        return 0;
    }

    let input_slice = unsafe { std::slice::from_raw_parts(in_buf, in_len) };
    let dummy_client: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();
    let response = DNS_FILTER.handle_dns_payload(input_slice, dummy_client);

    if response.is_empty() || response.len() > out_max_len {
        return 0;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(response.as_ptr(), out_buf, response.len());
    }

    response.len()
}

/// Process a raw IPv4 packet coming off the VPN TUN interface.
///
/// If the packet is a UDP/53 DNS query, it is filtered by the engine and a
/// fully-formed IPv4/UDP reply packet is written to `out_buf`; the reply length
/// is returned. Returns 0 when the packet is not a DNS query, is malformed, or
/// the reply would not fit in `out_max_len` (caller should then drop/forward it).
///
/// Desktop and iOS do not know which app sent a packet; Android passes it to
/// `aegis_process_ip_packet_for_uid` instead.
#[no_mangle]
pub extern "C" fn aegis_process_ip_packet(
    in_buf: *const u8,
    in_len: usize,
    out_buf: *mut u8,
    out_max_len: usize,
) -> usize {
    aegis_process_ip_packet_for_uid(
        in_buf,
        in_len,
        out_buf,
        out_max_len,
        crate::statistics::UNKNOWN_UID,
    )
}

/// Same as `aegis_process_ip_packet`, recording `uid` as the asking app (Android).
#[no_mangle]
pub extern "C" fn aegis_process_ip_packet_for_uid(
    in_buf: *const u8,
    in_len: usize,
    out_buf: *mut u8,
    out_max_len: usize,
    uid: i32,
) -> usize {
    if in_buf.is_null() || out_buf.is_null() || in_len == 0 {
        return 0;
    }

    let packet = unsafe { std::slice::from_raw_parts(in_buf, in_len) };
    let dummy_client: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();

    // Check IPv4 UDP port 53
    if let Some(p) = crate::packet::parse_ipv4_udp(packet) {
        if p.dst_port == 53 {
            let dns_response = DNS_FILTER.handle_dns_payload_for_uid(p.payload, dummy_client, uid);
            if dns_response.is_empty() {
                return 0;
            }

            let reply = match crate::packet::build_ipv4_udp_response(packet, &dns_response) {
                Some(r) => r,
                None => return 0,
            };

            if reply.len() > out_max_len {
                return 0;
            }

            unsafe {
                std::ptr::copy_nonoverlapping(reply.as_ptr(), out_buf, reply.len());
            }
            return reply.len();
        }
    }

    // Check IPv6 UDP port 53
    if let Some(p) = crate::packet::parse_ipv6_udp(packet) {
        if p.dst_port == 53 {
            let dns_response = DNS_FILTER.handle_dns_payload_for_uid(p.payload, dummy_client, uid);
            if dns_response.is_empty() {
                return 0;
            }

            let reply = match crate::packet::build_ipv6_udp_response(packet, &dns_response) {
                Some(r) => r,
                None => return 0,
            };

            if reply.len() > out_max_len {
                return 0;
            }

            unsafe {
                std::ptr::copy_nonoverlapping(reply.as_ptr(), out_buf, reply.len());
            }
            return reply.len();
        }
    }

    // Anything else here was sent to a public resolver address routed into
    // the tunnel to stop apps bypassing the filter (or is TCP to our own DNS
    // address). Refuse it at once so the app falls back to the system
    // resolver instead of waiting for a timeout.
    let refusal = match packet.first().map(|b| b >> 4) {
        Some(4) => crate::packet::build_tcp_reset_v4(packet)
            .or_else(|| crate::packet::build_udp_port_unreachable_v4(packet)),
        Some(6) => crate::packet::build_tcp_reset_v6(packet)
            .or_else(|| crate::packet::build_udp_port_unreachable_v6(packet)),
        _ => None,
    };
    match refusal {
        Some(reply) if reply.len() <= out_max_len => {
            unsafe {
                std::ptr::copy_nonoverlapping(reply.as_ptr(), out_buf, reply.len());
            }
            reply.len()
        }
        _ => 0,
    }
}

/// Block public DNS-over-HTTPS endpoint names (see `dns_filter::DOH_HOSTS`).
#[no_mangle]
pub extern "C" fn aegis_set_block_doh_hosts(enabled: c_int) {
    DNS_FILTER.set_block_doh_hosts(enabled != 0);
}

/// Replace the list of apps (Android UIDs) whose every lookup is refused.
/// `len == 0` clears it; `uids` may then be null.
#[no_mangle]
pub extern "C" fn aegis_set_blocked_uids(uids: *const i32, len: usize) {
    if uids.is_null() || len == 0 {
        DNS_FILTER.set_blocked_uids(&[]);
        return;
    }
    // SAFETY: the caller hands over `len` readable i32 values at `uids`.
    let list = unsafe { std::slice::from_raw_parts(uids, len) };
    DNS_FILTER.set_blocked_uids(list);
}

/// Get current statistics as JSON string
#[no_mangle]
pub extern "C" fn aegis_get_stats_json() -> *mut c_char {
    let summary = STATS_ENGINE.get_summary();
    let json = serde_json::to_string(&summary).unwrap_or_else(|_| "{}".to_string());
    CString::new(json).unwrap().into_raw()
}

/// Get recent DNS query log items as JSON string
#[no_mangle]
pub extern "C" fn aegis_get_recent_logs_json(limit: c_int) -> *mut c_char {
    let limit_val = if limit <= 0 { 50 } else { limit as usize };
    let logs = STATS_ENGINE.get_recent_logs(limit_val);
    let json = serde_json::to_string(&logs).unwrap_or_else(|_| "[]".to_string());
    CString::new(json).unwrap().into_raw()
}

/// Free string allocated by Rust
#[no_mangle]
pub extern "C" fn aegis_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::thread;

    /// IPv4+UDP+DNS frame carrying an A query for `host`, aimed at port 53.
    fn dns_packet(host: &str, txid: u16) -> Vec<u8> {
        let mut dns = vec![
            (txid >> 8) as u8,
            (txid & 0xff) as u8,
            0x01,
            0x00, // RD
            0x00,
            0x01, // QDCOUNT
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
        ];
        for label in host.split('.') {
            dns.push(label.len() as u8);
            dns.extend_from_slice(label.as_bytes());
        }
        dns.extend_from_slice(&[0x00, 0x00, 0x01, 0x00, 0x01]); // root, A, IN

        let total = 20 + 8 + dns.len();
        let mut p = vec![0u8; total];
        p[0] = 0x45;
        p[2..4].copy_from_slice(&(total as u16).to_be_bytes());
        p[8] = 64;
        p[9] = 17; // UDP
        p[12..16].copy_from_slice(&[10, 0, 0, 2]);
        p[16..20].copy_from_slice(&[10, 0, 0, 3]);
        let csum = crate::packet::internet_checksum(&p[..20]);
        p[10..12].copy_from_slice(&csum.to_be_bytes());
        p[20..22].copy_from_slice(&40000u16.to_be_bytes());
        p[22..24].copy_from_slice(&53u16.to_be_bytes());
        p[24..26].copy_from_slice(&((8 + dns.len()) as u16).to_be_bytes());
        p[28..].copy_from_slice(&dns);
        p
    }

    /// The tunnel loop hands packets to a pool of threads so a slow upstream
    /// lookup cannot stall every other query behind it. That is only sound if
    /// the engine tolerates concurrent callers, which is what this pins down:
    /// rule lookups, the stats ring and response building all run at once.
    #[test]
    fn process_ip_packet_is_safe_from_many_threads_at_once() {
        const THREADS: usize = 8;
        const PER_THREAD: usize = 50;

        let handles: Vec<_> = (0..THREADS)
            .map(|t| {
                thread::spawn(move || {
                    for i in 0..PER_THREAD {
                        let txid = (t * PER_THREAD + i) as u16;
                        // A seeded ad domain: answered from the rule engine, so
                        // the test never touches the network.
                        let packet = dns_packet("doubleclick.net", txid);
                        let mut out = vec![0u8; packet.len() + 1500];

                        let n = super::aegis_process_ip_packet(
                            packet.as_ptr(),
                            packet.len(),
                            out.as_mut_ptr(),
                            out.len(),
                        );

                        assert!(n > 0, "blocked query produced no reply");
                        let reply = crate::packet::parse_ipv4_udp(&out[..n])
                            .expect("reply is not a valid IPv4/UDP packet");

                        // Every reply must carry its own transaction id back —
                        // a torn or shared buffer would show up here.
                        assert_eq!(
                            u16::from_be_bytes([reply.payload[0], reply.payload[1]]),
                            txid,
                        );
                        // RCODE 3 = NXDOMAIN, the blocked answer.
                        assert_eq!(reply.payload[3] & 0x0f, 3);
                    }
                })
            })
            .collect();

        for h in handles {
            h.join().expect("a worker thread panicked");
        }
    }

    #[test]
    fn process_ip_packet_for_uid_records_the_uid() {
        // A UID no other test uses, so the shared engine's log can be searched.
        const UID: i32 = 4_242;
        let packet = dns_packet("doubleclick.net", 0x4242);
        let mut out = vec![0u8; packet.len() + 1500];

        let n = super::aegis_process_ip_packet_for_uid(
            packet.as_ptr(),
            packet.len(),
            out.as_mut_ptr(),
            out.len(),
            UID,
        );

        assert!(n > 0);
        assert!(super::STATS_ENGINE
            .get_recent_logs(1000)
            .iter()
            .any(|e| e.uid == UID && e.domain == "doubleclick.net"));
    }

    #[test]
    fn set_blocked_uids_takes_a_list_and_a_null_clears_it() {
        // UIDs no other test uses: the engine is shared by the whole binary.
        let uids = [7_301, 7_302];
        super::aegis_set_blocked_uids(uids.as_ptr(), uids.len());
        assert!(super::DNS_FILTER.is_uid_blocked(7_301));
        assert!(super::DNS_FILTER.is_uid_blocked(7_302));

        super::aegis_set_blocked_uids(std::ptr::null(), 0);
        assert!(!super::DNS_FILTER.is_uid_blocked(7_301));
        assert!(!super::DNS_FILTER.is_uid_blocked(7_302));
    }

    /// Android keeps the process alive for the VPN service after the activity
    /// is closed with Back; reopening the app starts a new Flutter engine,
    /// which initialises the native engine again in the same process. That
    /// used to abort the whole process — and the tunnel with it.
    #[test]
    fn init_can_run_more_than_once_in_a_process() {
        assert_eq!(super::aegis_init(), 1);
        assert_eq!(super::aegis_init(), 1);
    }

    fn run(packet: &[u8]) -> Vec<u8> {
        let mut out = vec![0u8; packet.len() + 1500];
        let n = super::aegis_process_ip_packet_for_uid(
            packet.as_ptr(),
            packet.len(),
            out.as_mut_ptr(),
            out.len(),
            -1,
        );
        out.truncate(n);
        out
    }

    #[test]
    fn tcp_reaching_the_tunnel_is_reset() {
        let mut syn = vec![0u8; 40];
        syn[0] = 0x45;
        syn[2..4].copy_from_slice(&40u16.to_be_bytes());
        syn[9] = 6;
        syn[12..16].copy_from_slice(&[10, 0, 0, 2]);
        syn[16..20].copy_from_slice(&[8, 8, 8, 8]);
        syn[20..22].copy_from_slice(&40000u16.to_be_bytes());
        syn[22..24].copy_from_slice(&853u16.to_be_bytes());
        syn[32] = 5 << 4;
        syn[33] = crate::packet::TCP_SYN;

        let reply = run(&syn);
        let (_, _, h) = crate::packet::parse_ipv4_tcp(&reply).expect("a TCP reply");
        assert_eq!(h.flags & crate::packet::TCP_RST, crate::packet::TCP_RST);
    }

    #[test]
    fn udp_to_another_port_gets_port_unreachable() {
        let mut quic = dns_packet("example.com", 1);
        quic[22..24].copy_from_slice(&443u16.to_be_bytes());
        let reply = run(&quic);
        assert_eq!(reply[9], 1, "ICMP");
        assert_eq!((reply[20], reply[21]), (3, 3));
    }

    #[test]
    fn plain_dns_to_a_public_resolver_is_filtered() {
        let mut query = dns_packet("doubleclick.net", 7);
        query[16..20].copy_from_slice(&[8, 8, 8, 8]);
        let csum = {
            query[10] = 0;
            query[11] = 0;
            crate::packet::internet_checksum(&query[..20])
        };
        query[10..12].copy_from_slice(&csum.to_be_bytes());

        let reply = run(&query);
        let udp = crate::packet::parse_ipv4_udp(&reply).expect("a DNS reply");
        assert_eq!(
            udp.src_ip,
            [8, 8, 8, 8],
            "answers as the resolver the app asked"
        );
        assert_eq!(udp.payload[3] & 0x0f, 3, "NXDOMAIN");
    }

    #[test]
    fn icmp_reaching_the_tunnel_is_dropped() {
        let mut echo = vec![0u8; 28];
        echo[0] = 0x45;
        echo[2..4].copy_from_slice(&28u16.to_be_bytes());
        echo[9] = 1;
        echo[20] = 8;
        assert!(run(&echo).is_empty());
    }
}
