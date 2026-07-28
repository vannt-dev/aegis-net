use std::collections::HashSet;
use std::sync::RwLock;
use log::{info, debug};

/// High-performance Domain Rule Matcher for AegisNet
pub struct RuleEngine {
    blocked_domains: RwLock<HashSet<String>>,
    allowed_domains: RwLock<HashSet<String>>,
    blocked_exact: RwLock<HashSet<String>>,
}

impl RuleEngine {
    pub fn new() -> Self {
        Self {
            blocked_domains: RwLock::new(HashSet::new()),
            allowed_domains: RwLock::new(HashSet::new()),
            blocked_exact: RwLock::new(HashSet::new()),
        }
    }

    /// Load raw rules text (Hosts format, EasyList DNS format, or plain list)
    pub fn load_rules_text(&self, content: &str) -> usize {
        let mut count = 0;
        let mut blocked = self.blocked_domains.write().unwrap();

        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with('!') {
                continue;
            }

            if let Some(domain) = Self::parse_rule_line(line) {
                blocked.insert(domain);
                count += 1;
            }
        }

        info!("Loaded {} rules into Rule Engine", count);
        count
    }

    /// Parse a single line from hosts or filter list
    fn parse_rule_line(line: &str) -> Option<String> {
        // Handle hosts format: 0.0.0.0 domain.com or 127.0.0.1 domain.com
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 && (parts[0] == "0.0.0.0" || parts[0] == "127.0.0.1") {
            let domain = parts[1].to_lowercase();
            if domain != "localhost" && domain != "broadcasthost" {
                return Some(domain);
            }
        }

        // Handle AdGuard / EasyList DNS format: ||example.com^
        if line.starts_with("||") && line.ends_with('^') {
            let domain = &line[2..line.len() - 1];
            return Some(domain.to_lowercase());
        }

        // Handle plain domain format: example.com
        if !line.contains(' ') && line.contains('.') {
            return Some(line.to_lowercase());
        }

        None
    }

    /// Add custom domain to Whitelist
    pub fn add_whitelist(&self, domain: &str) {
        let mut allowed = self.allowed_domains.write().unwrap();
        allowed.insert(domain.to_lowercase());
    }

    /// Add custom domain to Blacklist
    pub fn add_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.insert(domain.to_lowercase());
    }

    /// Remove custom domain from Whitelist
    pub fn remove_whitelist(&self, domain: &str) {
        let mut allowed = self.allowed_domains.write().unwrap();
        allowed.remove(&domain.to_lowercase());
    }

    /// Remove custom domain from Blacklist
    pub fn remove_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.remove(&domain.to_lowercase());
    }

    /// Check if a domain should be blocked
    pub fn is_blocked(&self, domain: &str) -> bool {
        let clean_domain = domain.trim_end_matches('.').to_lowercase();

        // 1. Check Whitelist first
        {
            let allowed = self.allowed_domains.read().unwrap();
            if allowed.contains(&clean_domain) {
                debug!("Domain {} is whitelisted", clean_domain);
                return false;
            }
        }

        // 2. Check Custom Blacklist
        {
            let exact = self.blocked_exact.read().unwrap();
            if exact.contains(&clean_domain) {
                return true;
            }
        }

        // 3. Check Main Filter Rules (Exact & Subdomain matches)
        let blocked = self.blocked_domains.read().unwrap();
        if blocked.contains(&clean_domain) {
            return true;
        }

        // Check parent domains (e.g. ad.doubleclick.net -> doubleclick.net)
        let parts: Vec<&str> = clean_domain.split('.').collect();
        for i in 1..parts.len().saturating_sub(1) {
            let parent_domain = parts[i..].join(".");
            if blocked.contains(&parent_domain) {
                return true;
            }
        }

        false
    }

    /// Clear all rules
    pub fn clear(&self) {
        self.blocked_domains.write().unwrap().clear();
        self.allowed_domains.write().unwrap().clear();
        self.blocked_exact.write().unwrap().clear();
    }
}
