use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::sync::Arc;
use lazy_static::lazy_static;
use crate::rule_engine::{RuleEngine, RuleCategory};
use crate::statistics::StatisticsEngine;
use crate::dns_filter::DnsFilterService;

lazy_static! {
    static ref RULE_ENGINE: Arc<RuleEngine> = Arc::new(RuleEngine::new());
    static ref STATS_ENGINE: Arc<StatisticsEngine> = Arc::new(StatisticsEngine::new(1000));
    // IP-literal DoH endpoint on purpose: when this engine runs behind a
    // DNS-capturing VPN, resolving a hostname here would recurse back into our
    // own resolver and deadlock. Cloudflare's certificate carries a 1.1.1.1 IP
    // SAN, so TLS verification still succeeds without any prior DNS lookup.
    static ref DNS_FILTER: Arc<DnsFilterService> = Arc::new(DnsFilterService::new(
        RULE_ENGINE.clone(),
        STATS_ENGINE.clone(),
        "https://1.1.1.1/dns-query".to_string()
    ));
}

/// Initialize Aegis Core Engine
#[no_mangle]
pub extern "C" fn aegis_init() -> c_int {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
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
}

/// Set the upstream DoH target used to resolve cache-miss queries. Accepts a
/// bare host/IP or a full `https://.../dns-query` URL.
#[no_mangle]
pub extern "C" fn aegis_set_upstream_dns(upstream_ptr: *const c_char) {
    if upstream_ptr.is_null() { return; }
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

/// Add domain to Whitelist
#[no_mangle]
pub extern "C" fn aegis_add_whitelist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() { return; }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.add_whitelist(domain);
    }
}

/// Add domain to Blacklist
#[no_mangle]
pub extern "C" fn aegis_add_blacklist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() { return; }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.add_blacklist(domain);
    }
}

/// Remove domain from Whitelist
#[no_mangle]
pub extern "C" fn aegis_remove_whitelist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() { return; }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.remove_whitelist(domain);
    }
}

/// Remove domain from Blacklist
#[no_mangle]
pub extern "C" fn aegis_remove_blacklist(domain_ptr: *const c_char) {
    if domain_ptr.is_null() { return; }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        RULE_ENGINE.remove_blacklist(domain);
    }
}

/// Check if domain is blocked
#[no_mangle]
pub extern "C" fn aegis_is_domain_blocked(domain_ptr: *const c_char) -> c_int {
    if domain_ptr.is_null() { return 0; }
    if let Ok(domain) = unsafe { CStr::from_ptr(domain_ptr) }.to_str() {
        if RULE_ENGINE.is_blocked(domain) { 1 } else { 0 }
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
#[no_mangle]
pub extern "C" fn aegis_process_ip_packet(
    in_buf: *const u8,
    in_len: usize,
    out_buf: *mut u8,
    out_max_len: usize,
) -> usize {
    if in_buf.is_null() || out_buf.is_null() || in_len == 0 {
        return 0;
    }

    let packet = unsafe { std::slice::from_raw_parts(in_buf, in_len) };

    // Only DNS (UDP port 53) queries are handled here.
    let parsed = match crate::packet::parse_ipv4_udp(packet) {
        Some(p) if p.dst_port == 53 => p,
        _ => return 0,
    };

    let dummy_client: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();
    let dns_response = DNS_FILTER.handle_dns_payload(parsed.payload, dummy_client);
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
    reply.len()
}

/// Get current statistics as JSON string
#[no_mangle]
pub extern "C" fn aegis_get_stats_json() -> *mut c_char {
    let summary = STATS_ENGINE.get_summary();
    let json = serde_json::to_string(&summary).unwrap_or_else(|_| "{}".to_string());
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
