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

#[derive(Default, Debug)]
struct TrieNode {
    is_terminal: bool,
    children: HashMap<String, TrieNode>,
}

/// Compact Domain Trie for high-performance sub-microsecond matching and low memory usage.
#[derive(Default, Debug)]
pub struct DomainTrie {
    root: TrieNode,
    count: usize,
}

impl DomainTrie {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn insert(&mut self, domain: &str) -> bool {
        let clean = domain.trim_end_matches('.').to_lowercase();
        if clean.is_empty() {
            return false;
        }
        let labels: Vec<&str> = clean.split('.').rev().collect();
        let mut current = &mut self.root;
        for label in labels {
            current = current.children.entry(label.to_string()).or_default();
        }
        if !current.is_terminal {
            current.is_terminal = true;
            self.count += 1;
            true
        } else {
            false
        }
    }

    pub fn remove(&mut self, domain: &str) -> bool {
        let clean = domain.trim_end_matches('.').to_lowercase();
        if clean.is_empty() {
            return false;
        }
        let labels: Vec<&str> = clean.split('.').rev().collect();

        fn remove_rec(node: &mut TrieNode, labels: &[&str], depth: usize) -> (bool, bool) {
            if depth == labels.len() {
                if node.is_terminal {
                    node.is_terminal = false;
                    return (true, node.children.is_empty());
                }
                return (false, false);
            }
            let label = labels[depth];
            if let Some(child) = node.children.get_mut(label) {
                let (removed, delete_child) = remove_rec(child, labels, depth + 1);
                if delete_child {
                    node.children.remove(label);
                }
                let empty_now = !node.is_terminal && node.children.is_empty();
                (removed, empty_now)
            } else {
                (false, false)
            }
        }

        let (removed, _) = remove_rec(&mut self.root, &labels, 0);
        if removed {
            self.count -= 1;
        }
        removed
    }

    pub fn matches(&self, domain: &str) -> bool {
        let clean = domain.trim_end_matches('.').to_lowercase();
        if clean.is_empty() {
            return false;
        }
        let labels: Vec<&str> = clean.split('.').rev().collect();
        let mut current = &self.root;
        for label in labels {
            if current.is_terminal {
                return true;
            }
            match current.children.get(label) {
                Some(next) => current = next,
                None => return false,
            }
        }
        current.is_terminal
    }

    pub fn clear(&mut self) {
        self.root.children.clear();
        self.root.is_terminal = false;
        self.count = 0;
    }

    pub fn shrink_to_fit(&mut self) {
        fn shrink_rec(node: &mut TrieNode) {
            node.children.shrink_to_fit();
            for child in node.children.values_mut() {
                shrink_rec(child);
            }
        }
        shrink_rec(&mut self.root);
    }

    pub fn to_vec(&self) -> Vec<String> {
        let mut result = Vec::new();
        fn collect_rec(node: &TrieNode, path: &mut Vec<String>, out: &mut Vec<String>) {
            if node.is_terminal {
                let mut rev_path = path.clone();
                rev_path.reverse();
                out.push(rev_path.join("."));
            }
            for (label, child) in &node.children {
                path.push(label.clone());
                collect_rec(child, path, out);
                path.pop();
            }
        }
        collect_rec(&self.root, &mut Vec::new(), &mut result);
        result.sort();
        result
    }

    pub fn len(&self) -> usize {
        self.count
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }
}

/// High-performance Domain Rule Matcher for AegisNet with Categories
pub struct RuleEngine {
    ads_rules: RwLock<DomainTrie>,
    tracker_rules: RwLock<DomainTrie>,
    malware_rules: RwLock<DomainTrie>,
    adult_rules: RwLock<DomainTrie>,

    enabled_categories: RwLock<HashSet<RuleCategory>>,
    allowed_domains: RwLock<DomainTrie>,
    blocked_exact: RwLock<DomainTrie>,
    custom_hosts: RwLock<HashMap<String, String>>,
}

impl RuleEngine {
    pub fn new() -> Self {
        let mut enabled = HashSet::new();
        enabled.insert(RuleCategory::Ads);
        enabled.insert(RuleCategory::Trackers);
        enabled.insert(RuleCategory::Malware);

        let engine = Self {
            ads_rules: RwLock::new(DomainTrie::new()),
            tracker_rules: RwLock::new(DomainTrie::new()),
            malware_rules: RwLock::new(DomainTrie::new()),
            adult_rules: RwLock::new(DomainTrie::new()),
            enabled_categories: RwLock::new(enabled),
            allowed_domains: RwLock::new(DomainTrie::new()),
            blocked_exact: RwLock::new(DomainTrie::new()),
            custom_hosts: RwLock::new(HashMap::new()),
        };

        engine.seed_default_rules();
        engine
    }

    fn seed_default_rules(&self) {
        let mut ads = self.ads_rules.write().unwrap();
        ads.insert("doubleclick.net");
        ads.insert("googleadservices.com");
        ads.insert("pagead2.googlesyndication.com");
        ads.insert("aniview.com");
        ads.insert("adnxs.com");
        ads.insert("ad.doubleclick.net");
        ads.insert("static.doubleclick.net");
        ads.insert("ads.youtube.com");

        let mut trackers = self.tracker_rules.write().unwrap();
        trackers.insert("graph.facebook.com");
        trackers.insert("telemetry.applovin.com");
        trackers.insert("tracking.vungle.com");
        trackers.insert("analytics.google.com");
        trackers.insert("s.youtube.com");
        trackers.insert("video-stats.l.google.com");
        trackers.insert("youtubei.googleapis.com");

        let mut malware = self.malware_rules.write().unwrap();
        malware.insert("crypto-miner.org");
        malware.insert("bad-malware-site.net");
        malware.insert("phishing-login.com");
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

            if let Some(domain) = Self::parse_exception_line(line) {
                if allowed.insert(&domain) {
                    count += 1;
                }
                continue;
            }

            if let Some(domain) = Self::parse_rule_line(line) {
                if rules.insert(&domain) {
                    count += 1;
                }
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

    fn parse_exception_line(line: &str) -> Option<String> {
        if line.starts_with("@@||") && line.ends_with('^') {
            let domain = &line[4..line.len() - 1];
            return Some(domain.to_lowercase());
        }
        None
    }

    fn parse_rule_line(line: &str) -> Option<String> {
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
        allowed.insert(domain);
    }

    pub fn add_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.insert(domain);
    }

    pub fn remove_whitelist(&self, domain: &str) {
        let mut allowed = self.allowed_domains.write().unwrap();
        allowed.remove(domain);
    }

    pub fn remove_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.remove(domain);
    }

    pub fn enabled_categories(&self) -> Vec<RuleCategory> {
        let enabled = self.enabled_categories.read().unwrap();
        let mut categories: Vec<RuleCategory> = enabled.iter().copied().collect();
        categories.sort_by_key(|c| *c as u8);
        categories
    }

    pub fn whitelist(&self) -> Vec<String> {
        self.allowed_domains.read().unwrap().to_vec()
    }

    pub fn blacklist(&self) -> Vec<String> {
        self.blocked_exact.read().unwrap().to_vec()
    }

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
            for d in whitelist {
                allowed.insert(d);
            }
        }
        let mut blocked = self.blocked_exact.write().unwrap();
        blocked.clear();
        for d in blacklist {
            blocked.insert(d);
        }
    }

    pub fn is_blocked(&self, domain: &str) -> bool {
        let clean_domain = domain.trim_end_matches('.').to_lowercase();

        // 1. Check Whitelist (covers domain & subdomains via Trie)
        {
            let allowed = self.allowed_domains.read().unwrap();
            if allowed.matches(&clean_domain) {
                return false;
            }
        }

        // 2. Check Blacklist
        {
            let exact = self.blocked_exact.read().unwrap();
            if exact.matches(&clean_domain) {
                return true;
            }
        }

        // 3. Check Enabled Categories
        let enabled = self.enabled_categories.read().unwrap();

        if enabled.contains(&RuleCategory::Ads)
            && self.ads_rules.read().unwrap().matches(&clean_domain)
        {
            return true;
        }

        if enabled.contains(&RuleCategory::Trackers)
            && self.tracker_rules.read().unwrap().matches(&clean_domain)
        {
            return true;
        }

        if enabled.contains(&RuleCategory::Malware)
            && self.malware_rules.read().unwrap().matches(&clean_domain)
        {
            return true;
        }

        if enabled.contains(&RuleCategory::Adult)
            && self.adult_rules.read().unwrap().matches(&clean_domain)
        {
            return true;
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
        assert!(engine.is_blocked("doubleclick.net"));

        engine.set_category_enabled(RuleCategory::Ads, false);
        assert!(!engine.is_blocked("doubleclick.net"));

        engine.set_category_enabled(RuleCategory::Ads, true);
        assert!(engine.is_blocked("doubleclick.net"));
    }

    #[test]
    fn test_whitelist_covers_subdomains() {
        let engine = RuleEngine::new();
        assert!(engine.is_blocked("graph.facebook.com"));

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
        let count = engine.load_rules_text("@@not-a-real-rule.com", RuleCategory::Ads);
        assert_eq!(count, 0);
        assert!(!engine.is_blocked("not-a-real-rule.com"));
    }

    #[test]
    fn test_tld_rule_blocks_every_domain_under_it() {
        let engine = RuleEngine::new();
        let count = engine.load_rules_text("||zip^", RuleCategory::Malware);
        assert_eq!(count, 1);

        assert!(engine.is_blocked("foo.bar.zip"));
        assert!(engine.is_blocked("invoice.zip"));
        assert!(engine.is_blocked("zip"));
        assert!(!engine.is_blocked("invoice.example"));
    }

    #[test]
    fn test_tld_exception_unblocks_every_domain_under_it() {
        let engine = RuleEngine::new();
        assert!(engine.is_blocked("graph.facebook.com"));

        let count = engine.load_rules_text("@@||com^", RuleCategory::Ads);
        assert_eq!(count, 1);

        assert!(!engine.is_blocked("graph.facebook.com"));
        assert!(engine.is_blocked("doubleclick.net"));
    }

    #[test]
    fn test_bare_tld_needs_the_adguard_syntax_to_load() {
        let engine = RuleEngine::new();
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
        assert!(!engine.is_blocked("notexample.com"));
        assert!(!engine.is_blocked("example.org"));
    }
}
