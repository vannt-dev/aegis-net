use log::info;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::RwLock;

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
    custom_hosts: RwLock<HashMap<String, String>>,
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
            custom_hosts: RwLock::new(HashMap::new()),
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
        ads.insert("ad.doubleclick.net".to_string());
        ads.insert("static.doubleclick.net".to_string());
        ads.insert("ads.youtube.com".to_string());

        let mut trackers = self.tracker_rules.write().unwrap();
        trackers.insert("graph.facebook.com".to_string());
        trackers.insert("telemetry.applovin.com".to_string());
        trackers.insert("tracking.vungle.com".to_string());
        trackers.insert("analytics.google.com".to_string());
        trackers.insert("s.youtube.com".to_string());
        trackers.insert("video-stats.l.google.com".to_string());
        trackers.insert("youtubei.googleapis.com".to_string());

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
        let mut allowed = self.allowed_domains.write().unwrap();

        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with('!') {
                continue;
            }

            // `@@||domain^` exception rules (AdGuard/EasyList) override every
            // category, so they belong in the whitelist, not the category set.
            if let Some(domain) = Self::parse_exception_line(line) {
                allowed.insert(domain);
                count += 1;
                continue;
            }

            if let Some(domain) = Self::parse_rule_line(line) {
                rules.insert(domain);
                count += 1;
            }
        }

        rules.shrink_to_fit();
        allowed.shrink_to_fit();

        info!("Loaded {} rules into category {:?}", count, category);
        count
    }

    pub fn add_custom_host(&self, domain: &str, ip: &str) {
        let mut hosts = self.custom_hosts.write().unwrap();
        hosts.insert(
            domain.trim_end_matches('.').to_lowercase(),
            ip.trim().to_string(),
        );
    }

    pub fn remove_custom_host(&self, domain: &str) {
        let mut hosts = self.custom_hosts.write().unwrap();
        hosts.remove(&domain.trim_end_matches('.').to_lowercase());
    }

    pub fn get_custom_host(&self, domain: &str) -> Option<String> {
        let hosts = self.custom_hosts.read().unwrap();
        hosts
            .get(&domain.trim_end_matches('.').to_lowercase())
            .cloned()
    }

    /// Parse an AdGuard/EasyList exception rule (`@@||domain^`), which
    /// un-blocks a domain regardless of which category blocked it.
    fn parse_exception_line(line: &str) -> Option<String> {
        if line.starts_with("@@||") && line.ends_with('^') {
            let domain = &line[4..line.len() - 1];
            return Some(domain.to_lowercase());
        }
        None
    }

    fn parse_rule_line(line: &str) -> Option<String> {
        // Exception rules are handled by `parse_exception_line` above; never
        // fall through and treat an unmatched `@@`-prefixed line as a block rule.
        if line.starts_with("@@") {
            return None;
        }

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

    /// Categories currently enabled, sorted for a stable snapshot on disk.
    pub fn enabled_categories(&self) -> Vec<RuleCategory> {
        let enabled = self.enabled_categories.read().unwrap();
        let mut categories: Vec<RuleCategory> = enabled.iter().copied().collect();
        categories.sort_by_key(|c| *c as u8);
        categories
    }

    pub fn whitelist(&self) -> Vec<String> {
        Self::sorted(&self.allowed_domains)
    }

    pub fn blacklist(&self) -> Vec<String> {
        Self::sorted(&self.blocked_exact)
    }

    /// Replace the user lists and category toggles wholesale. Used when a
    /// process adopts a snapshot produced by the other one, where "not in the
    /// snapshot" has to mean "removed", not "left alone".
    pub fn replace_user_state(
        &self,
        categories: &[RuleCategory],
        whitelist: &[String],
        blacklist: &[String],
    ) {
        {
            let mut enabled = self.enabled_categories.write().unwrap();
            enabled.clear();
            enabled.extend(categories.iter().copied());
        }
        {
            let mut allowed = self.allowed_domains.write().unwrap();
            allowed.clear();
            allowed.extend(whitelist.iter().map(|d| d.to_lowercase()));
        }
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.clear();
        blocked.extend(blacklist.iter().map(|d| d.to_lowercase()));
    }

    fn sorted(set: &RwLock<HashSet<String>>) -> Vec<String> {
        let mut items: Vec<String> = set.read().unwrap().iter().cloned().collect();
        items.sort();
        items
    }

    pub fn is_blocked(&self, domain: &str) -> bool {
        let clean_domain = domain.trim_end_matches('.').to_lowercase();

        // 1. Check Whitelist (covers the domain and any of its subdomains)
        {
            let allowed = self.allowed_domains.read().unwrap();
            if Self::set_matches_domain(&allowed, &clean_domain) {
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

        if enabled.contains(&RuleCategory::Ads) && self.matches_set(&self.ads_rules, &clean_domain)
        {
            return true;
        }

        if enabled.contains(&RuleCategory::Trackers)
            && self.matches_set(&self.tracker_rules, &clean_domain)
        {
            return true;
        }

        if enabled.contains(&RuleCategory::Malware)
            && self.matches_set(&self.malware_rules, &clean_domain)
        {
            return true;
        }

        if enabled.contains(&RuleCategory::Adult)
            && self.matches_set(&self.adult_rules, &clean_domain)
        {
            return true;
        }

        false
    }

    fn matches_set(&self, set: &RwLock<HashSet<String>>, domain: &str) -> bool {
        let rules = set.read().unwrap();
        Self::set_matches_domain(&rules, domain)
    }

    /// Returns true if `domain` equals a rule in `rules`, or is a subdomain of one.
    /// Performs zero heap allocations during subdomain hierarchy traversal.
    fn set_matches_domain(rules: &HashSet<String>, domain: &str) -> bool {
        if rules.contains(domain) {
            return true;
        }

        let mut slice = domain;
        while let Some(pos) = slice.find('.') {
            slice = &slice[pos + 1..];
            if slice.is_empty() {
                break;
            }
            if rules.contains(slice) {
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
        self.custom_hosts.write().unwrap().clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_custom_hosts_mapping() {
        let engine = RuleEngine::new();
        engine.add_custom_host("myrouter.local", "192.168.1.1");
        assert_eq!(
            engine.get_custom_host("myrouter.local"),
            Some("192.168.1.1".to_string())
        );

        engine.remove_custom_host("myrouter.local");
        assert_eq!(engine.get_custom_host("myrouter.local"), None);
    }

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
    fn test_disabling_category_stops_blocking() {
        let engine = RuleEngine::new();
        assert!(engine.is_blocked("doubleclick.net")); // Ads enabled by default

        engine.set_category_enabled(RuleCategory::Ads, false);
        assert!(!engine.is_blocked("doubleclick.net")); // category off -> allowed

        engine.set_category_enabled(RuleCategory::Ads, true);
        assert!(engine.is_blocked("doubleclick.net")); // re-enabled -> blocked
    }

    #[test]
    fn test_whitelist_covers_subdomains() {
        let engine = RuleEngine::new();
        // graph.facebook.com is a seeded tracker rule
        assert!(engine.is_blocked("graph.facebook.com"));

        // Whitelisting the parent domain should allow all its subdomains
        engine.add_whitelist("facebook.com");
        assert!(!engine.is_blocked("graph.facebook.com"));
        assert!(!engine.is_blocked("facebook.com"));
    }

    #[test]
    fn test_remove_whitelist_restores_blocking() {
        let engine = RuleEngine::new();
        engine.add_whitelist("doubleclick.net");
        assert!(!engine.is_blocked("doubleclick.net"));

        engine.remove_whitelist("doubleclick.net");
        assert!(engine.is_blocked("doubleclick.net"));
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

    #[test]
    fn test_exception_rule_unblocks_domain() {
        let engine = RuleEngine::new();
        let content = "||shady-ads.example^\n@@||shady-ads.example^";
        let count = engine.load_rules_text(content, RuleCategory::Ads);
        assert_eq!(count, 2);
        assert!(!engine.is_blocked("shady-ads.example"));
    }

    #[test]
    fn test_malformed_exception_line_is_ignored() {
        let engine = RuleEngine::new();
        // Not a well-formed `@@||domain^` rule; must not leak into the block set.
        let count = engine.load_rules_text("@@not-a-real-rule.com", RuleCategory::Ads);
        assert_eq!(count, 0);
        assert!(!engine.is_blocked("not-a-real-rule.com"));
    }

    // --- TLD boundary -------------------------------------------------------
    //
    // `set_matches_domain` walks every parent label including the last one, so a
    // rule holding a bare TLD covers the whole TLD. That is deliberate: `||zip^`
    // is how AdGuard lists express "block all of .zip", and stopping one label
    // short would make such a rule match only the literal string "zip" — that is,
    // nothing a resolver ever sees. The tests below pin the behaviour down in
    // both directions, because the same matcher backs the block sets and the
    // whitelist, and nothing else in the suite covers the last label.

    #[test]
    fn test_tld_rule_blocks_every_domain_under_it() {
        let engine = RuleEngine::new();
        let count = engine.load_rules_text("||zip^", RuleCategory::Malware);
        assert_eq!(count, 1);

        assert!(engine.is_blocked("foo.bar.zip"));
        assert!(engine.is_blocked("invoice.zip"));
        assert!(engine.is_blocked("zip"));
        // A neighbouring TLD is untouched.
        assert!(!engine.is_blocked("invoice.example"));
    }

    #[test]
    fn test_tld_exception_unblocks_every_domain_under_it() {
        let engine = RuleEngine::new();
        // graph.facebook.com is a seeded tracker rule.
        assert!(engine.is_blocked("graph.facebook.com"));

        let count = engine.load_rules_text("@@||com^", RuleCategory::Ads);
        assert_eq!(count, 1);

        // The exception lands in the whitelist, which outranks every category.
        assert!(!engine.is_blocked("graph.facebook.com"));
        // A domain outside .com keeps its verdict.
        assert!(engine.is_blocked("doubleclick.net"));
    }

    #[test]
    fn test_bare_tld_needs_the_adguard_syntax_to_load() {
        let engine = RuleEngine::new();
        // A plain line has to contain a dot to be read as a domain, so a stray
        // "com" in a list cannot silently swallow every .com. Only the explicit
        // `||com^` form does, which takes an author who meant it.
        let count = engine.load_rules_text("com", RuleCategory::Ads);
        assert_eq!(count, 0);
        assert!(!engine.is_blocked("example.com"));
    }

    #[test]
    fn test_subdomain_matching_stays_intact_below_the_tld() {
        let engine = RuleEngine::new();
        let count = engine.load_rules_text("||example.com^", RuleCategory::Ads);
        assert_eq!(count, 1);

        assert!(engine.is_blocked("example.com"));
        assert!(engine.is_blocked("ads.example.com"));
        assert!(engine.is_blocked("a.b.c.example.com"));
        // Sibling domains sharing only the TLD must not be caught.
        assert!(!engine.is_blocked("notexample.com"));
        assert!(!engine.is_blocked("example.org"));
    }
}
