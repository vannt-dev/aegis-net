use std::collections::HashSet;
use std::sync::RwLock;
use log::info;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RuleCategory {
    Ads,
    Trackers,
    Malware,
    Adult,
}

/// High-performance Domain Rule Matcher for AegisNet with Categories
pub struct RuleEngine {
    ads_rules: RwLock<HashSet<String>>,
    tracker_rules: RwLock<HashSet<String>>,
    malware_rules: RwLock<HashSet<String>>,
    adult_rules: RwLock<HashSet<String>>,

    enabled_categories: RwLock<HashSet<RuleCategory>>,
    allowed_domains: RwLock<HashSet<String>>,
    blocked_exact: RwLock<HashSet<String>>,
}

impl RuleEngine {
    pub fn new() -> Self {
        let mut enabled = HashSet::new();
        enabled.insert(RuleCategory::Ads);
        enabled.insert(RuleCategory::Trackers);
        enabled.insert(RuleCategory::Malware);

        let engine = Self {
            ads_rules: RwLock::new(HashSet::new()),
            tracker_rules: RwLock::new(HashSet::new()),
            malware_rules: RwLock::new(HashSet::new()),
            adult_rules: RwLock::new(HashSet::new()),
            enabled_categories: RwLock::new(enabled),
            allowed_domains: RwLock::new(HashSet::new()),
            blocked_exact: RwLock::new(HashSet::new()),
        };

        engine.seed_default_rules();
        engine
    }

    fn seed_default_rules(&self) {
        let mut ads = self.ads_rules.write().unwrap();
        ads.insert("doubleclick.net".to_string());
        ads.insert("googleadservices.com".to_string());
        ads.insert("pagead2.googlesyndication.com".to_string());
        ads.insert("aniview.com".to_string());
        ads.insert("adnxs.com".to_string());

        let mut trackers = self.tracker_rules.write().unwrap();
        trackers.insert("graph.facebook.com".to_string());
        trackers.insert("telemetry.applovin.com".to_string());
        trackers.insert("tracking.vungle.com".to_string());
        trackers.insert("analytics.google.com".to_string());

        let mut malware = self.malware_rules.write().unwrap();
        malware.insert("crypto-miner.org".to_string());
        malware.insert("bad-malware-site.net".to_string());
        malware.insert("phishing-login.com".to_string());
    }

    pub fn set_category_enabled(&self, category: RuleCategory, enabled: bool) {
        let mut categories = self.enabled_categories.write().unwrap();
        if enabled {
            categories.insert(category);
        } else {
            categories.remove(&category);
        }
    }

    pub fn load_rules_text(&self, content: &str, category: RuleCategory) -> usize {
        let mut count = 0;
        let target_set = match category {
            RuleCategory::Ads => &self.ads_rules,
            RuleCategory::Trackers => &self.tracker_rules,
            RuleCategory::Malware => &self.malware_rules,
            RuleCategory::Adult => &self.adult_rules,
        };

        let mut rules = target_set.write().unwrap();

        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with('!') {
                continue;
            }

            if let Some(domain) = Self::parse_rule_line(line) {
                rules.insert(domain);
                count += 1;
            }
        }

        info!("Loaded {} rules into category {:?}", count, category);
        count
    }

    fn parse_rule_line(line: &str) -> Option<String> {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 && (parts[0] == "0.0.0.0" || parts[0] == "127.0.0.1") {
            let domain = parts[1].to_lowercase();
            if domain != "localhost" && domain != "broadcasthost" {
                return Some(domain);
            }
        }

        if line.starts_with("||") && line.ends_with('^') {
            let domain = &line[2..line.len() - 1];
            return Some(domain.to_lowercase());
        }

        if !line.contains(' ') && line.contains('.') {
            return Some(line.to_lowercase());
        }

        None
    }

    pub fn add_whitelist(&self, domain: &str) {
        let mut allowed = self.allowed_domains.write().unwrap();
        allowed.insert(domain.to_lowercase());
    }

    pub fn add_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.insert(domain.to_lowercase());
    }

    pub fn remove_whitelist(&self, domain: &str) {
        let mut allowed = self.allowed_domains.write().unwrap();
        allowed.remove(&domain.to_lowercase());
    }

    pub fn remove_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.remove(&domain.to_lowercase());
    }

    pub fn is_blocked(&self, domain: &str) -> bool {
        let clean_domain = domain.trim_end_matches('.').to_lowercase();

        // 1. Check Whitelist
        {
            let allowed = self.allowed_domains.read().unwrap();
            if allowed.contains(&clean_domain) {
                return false;
            }
        }

        // 2. Check Blacklist
        {
            let exact = self.blocked_exact.read().unwrap();
            if exact.contains(&clean_domain) {
                return true;
            }
        }

        // 3. Check Enabled Categories
        let enabled = self.enabled_categories.read().unwrap();

        if enabled.contains(&RuleCategory::Ads) && self.matches_set(&self.ads_rules, &clean_domain) {
            return true;
        }

        if enabled.contains(&RuleCategory::Trackers) && self.matches_set(&self.tracker_rules, &clean_domain) {
            return true;
        }

        if enabled.contains(&RuleCategory::Malware) && self.matches_set(&self.malware_rules, &clean_domain) {
            return true;
        }

        if enabled.contains(&RuleCategory::Adult) && self.matches_set(&self.adult_rules, &clean_domain) {
            return true;
        }

        false
    }

    fn matches_set(&self, set: &RwLock<HashSet<String>>, domain: &str) -> bool {
        let rules = set.read().unwrap();
        if rules.contains(domain) {
            return true;
        }

        let parts: Vec<&str> = domain.split('.').collect();
        for i in 1..parts.len().saturating_sub(1) {
            let parent = parts[i..].join(".");
            if rules.contains(&parent) {
                return true;
            }
        }
        false
    }

    pub fn clear(&self) {
        self.ads_rules.write().unwrap().clear();
        self.tracker_rules.write().unwrap().clear();
        self.malware_rules.write().unwrap().clear();
        self.adult_rules.write().unwrap().clear();
        self.allowed_domains.write().unwrap().clear();
        self.blocked_exact.write().unwrap().clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_seed_rules_blocking() {
        let engine = RuleEngine::new();
        assert!(engine.is_blocked("doubleclick.net"));
        assert!(engine.is_blocked("sub.doubleclick.net"));
        assert!(engine.is_blocked("graph.facebook.com"));
        assert!(!engine.is_blocked("google.com"));
        assert!(!engine.is_blocked("github.com"));
    }

    #[test]
    fn test_whitelist_priority() {
        let engine = RuleEngine::new();
        assert!(engine.is_blocked("doubleclick.net"));

        engine.add_whitelist("doubleclick.net");
        assert!(!engine.is_blocked("doubleclick.net"));
    }

    #[test]
    fn test_hosts_rule_parsing() {
        let engine = RuleEngine::new();
        let hosts_content = "0.0.0.0 adserver.com\n127.0.0.1 tracker.net\n# Comment line";
        let count = engine.load_rules_text(hosts_content, RuleCategory::Ads);
        assert_eq!(count, 2);
        assert!(engine.is_blocked("adserver.com"));
        assert!(engine.is_blocked("tracker.net"));
    }

    #[test]
    fn test_easylist_rule_parsing() {
        let engine = RuleEngine::new();
        let easylist_content = "||badad.org^\n||banner.net^";
        let count = engine.load_rules_text(easylist_content, RuleCategory::Ads);
        assert_eq!(count, 2);
        assert!(engine.is_blocked("badad.org"));
        assert!(engine.is_blocked("banner.net"));
    }
}
