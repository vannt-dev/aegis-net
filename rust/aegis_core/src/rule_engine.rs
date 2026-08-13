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
    /// Children sorted by label, looked up by binary search.
    ///
    /// This was a `HashMap<String, TrieNode>`, which cost roughly 2.5–7.7x the
    /// memory of the flat `HashSet<String>` the trie replaced: every node paid
    /// a hash map's fixed overhead plus its own heap table, and a domain trie
    /// is overwhelmingly single-child chains. That does not matter much on
    /// Android, where the tunnel shares the app's address space, but the iOS
    /// PacketTunnel extension has a hard memory limit in the tens of MB and
    /// the default blocklists run to hundreds of thousands of rules — enough
    /// to get the extension killed outright.
    ///
    /// A sorted `Vec` of boxed labels stores one pointer-sized slot plus the
    /// label bytes per child, with no table and no spare capacity after
    /// `shrink_to_fit`. Fan-out is small at every level except the TLD roots,
    /// so binary search is not a meaningful cost.
    children: Vec<(Box<str>, TrieNode)>,
}

impl TrieNode {
    fn find(&self, label: &str) -> Option<&TrieNode> {
        self.children
            .binary_search_by(|(l, _)| (**l).cmp(label))
            .ok()
            .map(|i| &self.children[i].1)
    }
}

/// Domain matcher storing one node per DNS label, reversed, so a rule covers a
/// domain and everything under it in a single lookup.
///
/// Blocking a whole zone costs one terminal node rather than one entry per
/// host. See [`TrieNode::children`] for the memory trade-off this makes.
#[derive(Default, Debug)]
pub struct DomainTrie {
    root: TrieNode,
    count: usize,
}

impl DomainTrie {
    pub fn new() -> Self {
        Self::default()
    }

    /// Split a domain into labels, root label first, lowercased.
    fn labels(domain: &str) -> Option<Vec<String>> {
        let clean = domain.trim_end_matches('.').to_lowercase();
        if clean.is_empty() {
            return None;
        }
        Some(clean.split('.').rev().map(|l| l.to_string()).collect())
    }

    pub fn insert(&mut self, domain: &str) -> bool {
        let Some(labels) = Self::labels(domain) else {
            return false;
        };

        let mut current = &mut self.root;
        for label in labels {
            let index = match current
                .children
                .binary_search_by(|(l, _)| (**l).cmp(&label))
            {
                Ok(existing) => existing,
                Err(insert_at) => {
                    current
                        .children
                        .insert(insert_at, (label.into_boxed_str(), TrieNode::default()));
                    insert_at
                }
            };
            current = &mut current.children[index].1;
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
        let Some(labels) = Self::labels(domain) else {
            return false;
        };

        /// Returns (did we clear a terminal, is this node now droppable).
        fn remove_rec(node: &mut TrieNode, labels: &[String], depth: usize) -> (bool, bool) {
            if depth == labels.len() {
                if node.is_terminal {
                    node.is_terminal = false;
                    return (true, node.children.is_empty());
                }
                return (false, false);
            }

            let label = &labels[depth];
            let Ok(index) = node.children.binary_search_by(|(l, _)| (**l).cmp(label)) else {
                return (false, false);
            };

            let (removed, drop_child) = remove_rec(&mut node.children[index].1, labels, depth + 1);
            if drop_child {
                node.children.remove(index);
            }
            (removed, !node.is_terminal && node.children.is_empty())
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

        let mut current = &self.root;
        for label in clean.split('.').rev() {
            // A terminal above the queried name means a parent zone is listed,
            // which covers every subdomain under it.
            if current.is_terminal {
                return true;
            }
            match current.find(label) {
                Some(next) => current = next,
                None => return false,
            }
        }
        current.is_terminal
    }

    pub fn clear(&mut self) {
        self.root.children.clear();
        self.root.children.shrink_to_fit();
        self.root.is_terminal = false;
        self.count = 0;
    }

    /// Hand back every byte of spare capacity in the tree. Worth calling after
    /// a bulk load: inserts grow each child vector geometrically, so a freshly
    /// loaded blocklist carries up to twice the slots it needs.
    pub fn shrink_to_fit(&mut self) {
        fn shrink_rec(node: &mut TrieNode) {
            node.children.shrink_to_fit();
            for (_, child) in node.children.iter_mut() {
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
                path.push(label.to_string());
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

/// What one line of a filter list means to the DNS matcher.
///
/// This is the distinction the parser actually draws, so it is worth a name:
/// `Unusable` is not a malformed line, it is valid filter syntax that a DNS
/// filter has no way to honour.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LineKind {
    /// A hostname to block, covering everything under it.
    Block(String),
    /// A hostname to allow, overriding every category (`@@||domain^`).
    Allow(String),
    /// Blank or a comment. Carries no rule.
    Comment,
    /// Rule syntax a DNS filter cannot express — wildcards, regex, and rules
    /// narrowed to a URL path or a resource type. Dropped on purpose.
    Unusable,
}

/// High-performance Domain Rule Matcher for AegisNet with Categories
pub struct RuleEngine {
    ads_rules: RwLock<DomainTrie>,
    tracker_rules: RwLock<DomainTrie>,
    malware_rules: RwLock<DomainTrie>,
    adult_rules: RwLock<DomainTrie>,

    enabled_categories: RwLock<HashSet<RuleCategory>>,
    /// User allowlist. Covers a domain and everything under it.
    allowed_domains: RwLock<DomainTrie>,
    /// User denylist. Also covers subdomains — blocking `example.com` blocks
    /// `ads.example.com` too. This was an exact-match set before the trie
    /// landed, so a rule that used to need one entry per host now needs one
    /// entry per zone.
    blocked_domains: RwLock<DomainTrie>,
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
            blocked_domains: RwLock::new(DomainTrie::new()),
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
            match Self::parse_line(line) {
                // `@@||domain^` exception rules (AdGuard/EasyList) override
                // every category, so they belong in the whitelist, not the
                // category set.
                LineKind::Allow(domain) => {
                    if allowed.insert(&domain) {
                        count += 1;
                    }
                }
                LineKind::Block(domain) => {
                    if rules.insert(&domain) {
                        count += 1;
                    }
                }
                LineKind::Comment | LineKind::Unusable => {}
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

    /// Every override as `(domain, ip)` pairs, sorted for a stable snapshot on
    /// disk.
    pub fn custom_hosts(&self) -> Vec<(String, String)> {
        let hosts = self.custom_hosts.read().unwrap();
        let mut pairs: Vec<(String, String)> = hosts
            .iter()
            .map(|(d, ip)| (d.clone(), ip.clone()))
            .collect();
        pairs.sort();
        pairs
    }

    /// Classify one line of a filter list.
    ///
    /// This is the single decision `load_rules_text` makes per line, exposed
    /// so a candidate list can be measured before it ships — see
    /// `examples/probe.rs`, which reports how many domains a list adds and
    /// what it costs in the trie. That tool used to carry its own copy of this
    /// logic; a copy does not fail when it drifts, it quietly reports wrong
    /// numbers, and those numbers are what list decisions get made on.
    pub fn parse_line(line: &str) -> LineKind {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with('!') {
            return LineKind::Comment;
        }

        if let Some(domain) = Self::parse_exception_line(line) {
            return LineKind::Allow(domain);
        }

        match Self::parse_rule_line(line) {
            Some(domain) => LineKind::Block(domain),
            None => LineKind::Unusable,
        }
    }

    /// Parse an AdGuard/EasyList exception rule (`@@||domain^`), which
    /// un-blocks a domain regardless of which category blocked it.
    ///
    /// The trailing `^` is optional here for the same reason it is optional on
    /// a block rule. `@@` alone is not enough: `@@not-a-real-rule.com` is not
    /// an exception rule, and treating it as one would silently un-block a
    /// domain — over-blocking is bad, but wrongly *allowing* something is
    /// worse for a filter.
    fn parse_exception_line(line: &str) -> Option<String> {
        if let Some(body) = line.strip_prefix("@@||") {
            return Self::extract_hostname(body, false);
        }
        None
    }

    /// Pull a bare hostname out of an AdGuard/EasyList rule body.
    ///
    /// Returns `None` for everything the DNS matcher cannot represent —
    /// wildcards, regex, and rules narrowed to a URL path or a resource type.
    /// Those used to reach a catch-all branch that stored the raw line as
    /// though it were a domain. Measured against the lists actually shipped:
    /// 669 such entries in the AdGuard DNS filter and 17,779 in EasyList, none
    /// of which can match any query, every one of them counted in the "rules
    /// loaded" figure shown to the user.
    ///
    /// `require_dot` separates the two syntaxes. `||zip^` deliberately blocks a
    /// whole TLD, so the `||` form has to accept a dotless name; a bare line
    /// has to look like a domain first, or every stray word in a list becomes
    /// a rule.
    fn extract_hostname(body: &str, require_dot: bool) -> Option<String> {
        // A network rule stops describing the hostname at the first of these:
        // the `^` separator, a path, `$` modifiers, or an option list.
        let host = body
            .split(['^', '/', '$', ',', '='])
            .next()?
            .trim()
            .trim_end_matches('.')
            .to_lowercase();

        if host.is_empty() || (require_dot && !host.contains('.')) {
            return None;
        }
        if host.starts_with('.') || host.starts_with('-') {
            return None;
        }
        // Anything outside this set means it is not a hostname: `*` wildcards,
        // regex punctuation, query-string fragments.
        if !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_')
        {
            return None;
        }
        // `a..b` is not a name; an empty label would also break trie traversal.
        if host.split('.').any(|label| label.is_empty()) {
            return None;
        }

        Some(host)
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
                return Self::extract_hostname(&domain, true);
            }
        }

        // `||domain^` and `||domain` are the same rule — the trailing separator
        // is optional, and 172 rules in the AdGuard DNS filter omit it.
        // Requiring it sent those to the fallback below, which stored them with
        // the `||` still attached, so they never matched a single query while
        // the UI counted them as loaded.
        if let Some(body) = line.strip_prefix("||") {
            return Self::extract_hostname(body, false);
        }

        Self::extract_hostname(line, true)
    }

    pub fn add_whitelist(&self, domain: &str) {
        let mut allowed = self.allowed_domains.write().unwrap();
        allowed.insert(domain);
    }

    pub fn add_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_domains.write().unwrap();
        blocked.insert(domain);
    }

    pub fn remove_whitelist(&self, domain: &str) {
        let mut allowed = self.allowed_domains.write().unwrap();
        allowed.remove(domain);
    }

    pub fn remove_blacklist(&self, domain: &str) {
        let mut blocked = self.blocked_domains.write().unwrap();
        blocked.remove(domain);
    }

    /// Categories currently enabled, sorted for a stable snapshot on disk.
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
        self.blocked_domains.read().unwrap().to_vec()
    }

    /// Replace the user lists and category toggles wholesale. Used when a
    /// process adopts a snapshot produced by the other one, where "not in the
    /// snapshot" has to mean "removed", not "left alone".
    pub fn replace_user_state(
        &self,
        categories: &[RuleCategory],
        whitelist: &[String],
        blacklist: &[String],
        custom_hosts: &[(String, String)],
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
        {
            let mut blocked = self.blocked_domains.write().unwrap();
            blocked.clear();
            for d in blacklist {
                blocked.insert(d);
            }
        }
        let mut hosts = self.custom_hosts.write().unwrap();
        hosts.clear();
        for (domain, ip) in custom_hosts {
            hosts.insert(
                domain.trim_end_matches('.').to_lowercase(),
                ip.trim().to_string(),
            );
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

        // 2. Check Blacklist (covers the domain and any of its subdomains)
        {
            let blocked = self.blocked_domains.read().unwrap();
            if blocked.matches(&clean_domain) {
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

    /// Wipe everything, including the user's own allow/deny lists and host
    /// overrides. Nothing routine should need this; see
    /// [`clear_downloaded_rules`](Self::clear_downloaded_rules).
    pub fn clear(&self) {
        self.ads_rules.write().unwrap().clear();
        self.tracker_rules.write().unwrap().clear();
        self.malware_rules.write().unwrap().clear();
        self.adult_rules.write().unwrap().clear();
        self.allowed_domains.write().unwrap().clear();
        self.blocked_domains.write().unwrap().clear();
        self.custom_hosts.write().unwrap().clear();
    }

    /// Drop every rule that came from a downloaded filter list, then restore
    /// the built-in seeds. The user's allow/deny lists and host overrides are
    /// left alone.
    ///
    /// Loading a list only ever inserted, so without this a blocklist the user
    /// unsubscribed from kept blocking until the process restarted — and on
    /// iOS the extension reloads repeatedly inside one process lifetime, so it
    /// never restarted at all.
    ///
    /// The seeds are re-applied because a sync that fails after this point
    /// would otherwise leave the engine with no rules whatsoever, which is
    /// worse than the state it started in.
    pub fn clear_downloaded_rules(&self) {
        self.ads_rules.write().unwrap().clear();
        self.tracker_rules.write().unwrap().clear();
        self.malware_rules.write().unwrap().clear();
        self.adult_rules.write().unwrap().clear();
        self.seed_default_rules();
        info!("Cleared downloaded filter rules; built-in seeds restored");
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
    fn test_block_rule_without_a_trailing_separator_still_loads() {
        // 172 rules in the shipping AdGuard DNS filter are written this way.
        // They used to fall through to the bare-line branch, which stored them
        // with the `||` still attached, so they matched nothing at all.
        let engine = RuleEngine::new();
        let count = engine.load_rules_text("||direct-specific.com", RuleCategory::Ads);

        assert_eq!(count, 1);
        assert!(engine.is_blocked("direct-specific.com"));
        assert!(engine.is_blocked("sub.direct-specific.com"));
    }

    #[test]
    fn test_exception_without_a_trailing_separator_still_loads() {
        let engine = RuleEngine::new();
        let count =
            engine.load_rules_text("||shady.example^\n@@||shady.example", RuleCategory::Ads);

        assert_eq!(count, 2);
        assert!(!engine.is_blocked("shady.example"));
    }

    #[test]
    fn test_rules_the_dns_matcher_cannot_express_are_dropped() {
        // Every one of these used to be stored verbatim as a "domain": they
        // occupy memory, inflate the rule count reported to the user, and can
        // never match a query. A DNS filter sees a hostname and nothing else.
        let engine = RuleEngine::new();
        let unusable = [
            "||ads.livetv*.me^",                   // wildcard
            "/^139\\.45\\.197\\.2(4[0-9])/",       // regex
            "-ads-manager/$domain=~wordpress.org", // path + modifier
            "-ad-sidebar.$image",                  // resource type
            "&sst.gcsub=",                         // query-string fragment
            ".beacon.min.js",                      // leading dot, not a name
            "example.com##.ad-banner",             // cosmetic filter
            "||a..b^",                             // empty label
        ];

        let count = engine.load_rules_text(&unusable.join("\n"), RuleCategory::Ads);
        assert_eq!(count, 0, "nothing here is a hostname");
    }

    #[test]
    fn test_modifiers_and_separators_are_stripped_to_the_hostname() {
        let engine = RuleEngine::new();
        let count = engine.load_rules_text(
            "||tracker.example^$important\n||other.example^third-party",
            RuleCategory::Trackers,
        );

        assert_eq!(count, 2);
        assert!(engine.is_blocked("tracker.example"));
        assert!(engine.is_blocked("other.example"));
    }

    #[test]
    fn test_clearing_downloaded_rules_keeps_user_lists_and_seeds() {
        let engine = RuleEngine::new();
        engine.load_rules_text("0.0.0.0 tracker.example.com", RuleCategory::Ads);
        engine.add_blacklist("mine.example.net");
        engine.add_whitelist("safe.example.org");
        engine.add_custom_host("myrouter.local", "192.168.1.1");
        assert!(engine.is_blocked("tracker.example.com"));

        engine.clear_downloaded_rules();

        // The downloaded rule is gone — unsubscribing has to take effect.
        assert!(!engine.is_blocked("tracker.example.com"));
        // The user's own state is untouched.
        assert!(engine.is_blocked("mine.example.net"));
        assert_eq!(
            engine.get_custom_host("myrouter.local"),
            Some("192.168.1.1".to_string())
        );
        assert!(engine.whitelist().contains(&"safe.example.org".to_string()));
        // And the built-in seeds are back, so a failed sync is not a total
        // loss of protection.
        assert!(engine.is_blocked("doubleclick.net"));
    }

    #[test]
    fn test_blacklisting_a_domain_covers_its_subdomains() {
        // The denylist was an exact-match set before the trie; one entry per
        // host is no longer needed, and the change is easy to undo by accident.
        let engine = RuleEngine::new();
        engine.add_blacklist("example.com");

        assert!(engine.is_blocked("example.com"));
        assert!(engine.is_blocked("ads.example.com"));
        assert!(engine.is_blocked("deep.ads.example.com"));

        // A neighbour that merely ends in the same letters is not a subdomain.
        assert!(!engine.is_blocked("notexample.com"));

        engine.remove_blacklist("example.com");
        assert!(!engine.is_blocked("ads.example.com"));
    }

    #[test]
    fn test_whitelist_beats_a_blacklisted_parent_zone() {
        let engine = RuleEngine::new();
        engine.add_blacklist("example.com");
        engine.add_whitelist("safe.example.com");

        assert!(engine.is_blocked("example.com"));
        assert!(!engine.is_blocked("safe.example.com"));
    }

    #[test]
    fn test_custom_hosts_survive_a_snapshot_round_trip() {
        let engine = RuleEngine::new();
        engine.add_custom_host("myrouter.local", "192.168.1.1");
        engine.add_custom_host("nas.local", "192.168.1.9");

        // Sorted, so two snapshots of the same state compare equal.
        assert_eq!(
            engine.custom_hosts(),
            vec![
                ("myrouter.local".to_string(), "192.168.1.1".to_string()),
                ("nas.local".to_string(), "192.168.1.9".to_string()),
            ]
        );

        // Adopting a snapshot means "not present" is a removal, not a no-op.
        let adopted = vec![("nas.local".to_string(), "10.0.0.9".to_string())];
        engine.replace_user_state(&[], &[], &[], &adopted);

        assert_eq!(engine.get_custom_host("myrouter.local"), None);
        assert_eq!(
            engine.get_custom_host("nas.local"),
            Some("10.0.0.9".to_string())
        );
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
