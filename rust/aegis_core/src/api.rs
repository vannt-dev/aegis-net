use std::sync::Arc;
use lazy_static::lazy_static;
use crate::rule_engine::RuleEngine;
use crate::statistics::StatisticsEngine;
use crate::dns_filter::DnsFilterService;

lazy_static! {
    static ref RULE_ENGINE: Arc<RuleEngine> = Arc::new(RuleEngine::new());
    static ref STATS_ENGINE: Arc<StatisticsEngine> = Arc::new(StatisticsEngine::new(500));
    static ref DNS_FILTER: Arc<DnsFilterService> = Arc::new(DnsFilterService::new(
        RULE_ENGINE.clone(),
        STATS_ENGINE.clone(),
        "1.1.1.1".to_string()
    ));
}

/// Initialize Aegis Core Engine
pub fn init_engine() -> bool {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
    log::info!("Aegis Core Engine Initialized Successfully");
    true
}

/// Load filter rules text into engine (Returns count of rules added)
pub fn load_rules(rules_text: String) -> u32 {
    RULE_ENGINE.load_rules_text(&rules_text) as u32
}

/// Add domain to Whitelist
pub fn add_whitelist(domain: String) {
    RULE_ENGINE.add_whitelist(&domain);
}

/// Add domain to Blacklist
pub fn add_blacklist(domain: String) {
    RULE_ENGINE.add_blacklist(&domain);
}

/// Remove domain from Whitelist
pub fn remove_whitelist(domain: String) {
    RULE_ENGINE.remove_whitelist(&domain);
}

/// Remove domain from Blacklist
pub fn remove_blacklist(domain: String) {
    RULE_ENGINE.remove_blacklist(&domain);
}

/// Check if a domain is blocked by current active rules
pub fn is_domain_blocked(domain: String) -> bool {
    RULE_ENGINE.is_blocked(&domain)
}

/// Process a raw DNS UDP payload (used by Android VpnService & iOS PacketTunnelProvider)
pub fn handle_dns_packet(payload: Vec<u8>) -> Vec<u8> {
    let dummy_client: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();
    DNS_FILTER.handle_dns_payload(&payload, dummy_client)
}

/// Get current filtering statistics as JSON string
pub fn get_stats_json() -> String {
    let summary = STATS_ENGINE.get_summary();
    serde_json::to_string(&summary).unwrap_or_else(|_| "{}".to_string())
}

/// Get recent query logs as JSON string
pub fn get_logs_json(limit: u32) -> String {
    let logs = STATS_ENGINE.get_recent_logs(limit as usize);
    serde_json::to_string(&logs).unwrap_or_else(|_| "[]".to_string())
}

/// Reset statistics and logs
pub fn reset_stats() {
    STATS_ENGINE.reset();
}

/// Clear all filter rules
pub fn clear_rules() {
    RULE_ENGINE.clear();
}
