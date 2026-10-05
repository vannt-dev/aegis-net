use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::RwLock;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DnsLogEntry {
    pub id: u64,
    pub timestamp: u64,
    pub domain: String,
    pub blocked: bool,
    /// The app that asked, or `UNKNOWN_UID`.
    #[serde(default = "unknown_uid")]
    pub uid: i32,
}

/// Distinct domains the top-N tracker keeps per direction before evicting the
/// coldest half. Sized to hold far more than a top-5 needs while staying a
/// bounded, predictable amount of memory on a phone.
const MAX_TRACKED_DOMAINS: usize = 2_000;

/// How many domains each top list reports.
const TOP_DOMAIN_COUNT: usize = 5;

/// UID recorded when the app behind a query is not known: below Android 10,
/// on iOS and desktop, or when the platform refuses to say.
pub const UNKNOWN_UID: i32 = -1;

/// Distinct apps tracked before the quietest half is dropped. A phone has a
/// few hundred apps at most, so this rarely triggers.
const MAX_TRACKED_APPS: usize = 500;

/// How many apps the top list reports.
const TOP_APP_COUNT: usize = 20;

fn unknown_uid() -> i32 {
    UNKNOWN_UID
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainCount {
    pub domain: String,
    pub count: u64,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct AppTally {
    total: u64,
    blocked: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppCount {
    pub uid: i32,
    pub total: u64,
    pub blocked: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatsSummary {
    pub total_queries: u64,
    pub blocked_queries: u64,
    pub allowed_queries: u64,
    pub block_rate_percentage: f64,
    pub estimated_data_saved_bytes: u64,
    pub top_blocked: Vec<DomainCount>,
    pub top_allowed: Vec<DomainCount>,
    /// Busiest apps by query count. Missing in snapshots from before 1.4.
    #[serde(default)]
    pub top_apps: Vec<AppCount>,
}

pub struct StatisticsEngine {
    total_queries: AtomicU64,
    blocked_queries: AtomicU64,
    logs: RwLock<VecDeque<DnsLogEntry>>,
    blocked_counts: RwLock<HashMap<String, u64>>,
    allowed_counts: RwLock<HashMap<String, u64>>,
    app_counts: RwLock<HashMap<i32, AppTally>>,
    max_log_capacity: usize,
    counter_id: AtomicU64,
}

impl StatisticsEngine {
    pub fn new(max_log_capacity: usize) -> Self {
        Self {
            total_queries: AtomicU64::new(0),
            blocked_queries: AtomicU64::new(0),
            logs: RwLock::new(VecDeque::with_capacity(max_log_capacity)),
            blocked_counts: RwLock::new(HashMap::new()),
            allowed_counts: RwLock::new(HashMap::new()),
            app_counts: RwLock::new(HashMap::new()),
            max_log_capacity,
            counter_id: AtomicU64::new(1),
        }
    }

    pub fn record_request(&self, domain: &str, blocked: bool) {
        self.record_request_for_uid(domain, blocked, UNKNOWN_UID);
    }

    pub fn record_request_for_uid(&self, domain: &str, blocked: bool, uid: i32) {
        self.total_queries.fetch_add(1, Ordering::Relaxed);
        let domain_str = domain.to_string();

        if blocked {
            self.blocked_queries.fetch_add(1, Ordering::Relaxed);
            Self::record_domain(&self.blocked_counts, domain);
        } else {
            Self::record_domain(&self.allowed_counts, domain);
        }
        self.record_app(uid, blocked);

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let id = self.counter_id.fetch_add(1, Ordering::Relaxed);

        let entry = DnsLogEntry {
            id,
            timestamp,
            domain: domain_str,
            blocked,
            uid,
        };

        let mut logs = self.logs.write().unwrap();
        if logs.len() >= self.max_log_capacity {
            logs.pop_back();
        }
        logs.push_front(entry);
    }

    /// Count a query against the app that made it, keeping the table bounded
    /// the same way the domain tables are.
    fn record_app(&self, uid: i32, blocked: bool) {
        let mut apps = self.app_counts.write().unwrap();
        if !apps.contains_key(&uid) && apps.len() >= MAX_TRACKED_APPS {
            let keep = MAX_TRACKED_APPS / 2;
            let mut entries: Vec<(i32, AppTally)> = apps.drain().collect();
            entries.select_nth_unstable_by(keep, |a, b| b.1.total.cmp(&a.1.total));
            entries.truncate(keep);
            *apps = entries.into_iter().collect();
        }
        let tally = apps.entry(uid).or_default();
        tally.total += 1;
        if blocked {
            tally.blocked += 1;
        }
    }

    /// The busiest apps, highest first; ties ordered by UID so the list is stable.
    fn top_apps(&self) -> Vec<AppCount> {
        let apps = self.app_counts.read().unwrap();
        let mut items: Vec<AppCount> = apps
            .iter()
            .map(|(uid, tally)| AppCount {
                uid: *uid,
                total: tally.total,
                blocked: tally.blocked,
            })
            .collect();
        items.sort_unstable_by(|a, b| b.total.cmp(&a.total).then(a.uid.cmp(&b.uid)));
        items.truncate(TOP_APP_COUNT);
        items
    }

    /// Bump a domain's hit count, keeping the table bounded.
    ///
    /// Every distinct name a device looks up would otherwise earn a permanent
    /// entry here. A phone resolving CDN and telemetry hostnames all day
    /// reaches six figures of unique names within days, and the table is only
    /// ever read to show a top-5 list, so the tail is pure overhead.
    fn record_domain(counts: &RwLock<HashMap<String, u64>>, domain: &str) {
        let mut counts = counts.write().unwrap();

        if let Some(count) = counts.get_mut(domain) {
            *count += 1;
            return;
        }

        if counts.len() >= MAX_TRACKED_DOMAINS {
            Self::evict_coldest(&mut counts);
        }
        counts.insert(domain.to_string(), 1);
    }

    /// Drop everything outside the busiest half of the table.
    ///
    /// Halving rather than evicting one entry per insert keeps this off the
    /// hot path: it runs once per `MAX_TRACKED_DOMAINS / 2` new domains. The
    /// one-hit names it discards are exactly the ones that can never surface
    /// in a top-5, so the visible result is unchanged.
    fn evict_coldest(counts: &mut HashMap<String, u64>) {
        let keep = MAX_TRACKED_DOMAINS / 2;
        let mut entries: Vec<(String, u64)> = counts.drain().collect();

        if entries.len() > keep {
            entries.select_nth_unstable_by(keep, |a, b| b.1.cmp(&a.1));
            entries.truncate(keep);
        }

        *counts = entries.into_iter().collect();
    }

    /// The `n` most-hit domains, highest first.
    ///
    /// Selection is linear and only the survivors are cloned. Sorting the
    /// whole table and cloning every key — which is what this replaced — ran
    /// on each UI poll, twice, a few seconds apart.
    fn top_n(counts: &RwLock<HashMap<String, u64>>, n: usize) -> Vec<DomainCount> {
        let counts = counts.read().unwrap();
        let mut items: Vec<(&String, &u64)> = counts.iter().collect();

        if items.len() > n {
            items.select_nth_unstable_by(n, |a, b| b.1.cmp(a.1));
            items.truncate(n);
        }
        items.sort_unstable_by(|a, b| b.1.cmp(a.1));

        items
            .into_iter()
            .map(|(domain, count)| DomainCount {
                domain: domain.clone(),
                count: *count,
            })
            .collect()
    }

    pub fn get_summary(&self) -> StatsSummary {
        let total = self.total_queries.load(Ordering::Relaxed);
        let blocked = self.blocked_queries.load(Ordering::Relaxed);
        let allowed = total.saturating_sub(blocked);

        let block_rate = if total > 0 {
            (blocked as f64 / total as f64) * 100.0
        } else {
            0.0
        };

        // Estimate ~150KB saved per blocked ad request
        let data_saved = blocked * 150 * 1024;

        let top_blocked = Self::top_n(&self.blocked_counts, TOP_DOMAIN_COUNT);
        let top_allowed = Self::top_n(&self.allowed_counts, TOP_DOMAIN_COUNT);

        StatsSummary {
            total_queries: total,
            blocked_queries: blocked,
            allowed_queries: allowed,
            block_rate_percentage: block_rate,
            estimated_data_saved_bytes: data_saved,
            top_blocked,
            top_allowed,
            top_apps: self.top_apps(),
        }
    }

    /// Adopt statistics produced by another process (the iOS PacketTunnel
    /// extension). The counters and the top lists cross the boundary; the log
    /// ring stays local, since it is display-only and would bloat the snapshot.
    pub fn apply_summary(&self, summary: &StatsSummary) {
        self.total_queries
            .store(summary.total_queries, Ordering::Relaxed);
        self.blocked_queries
            .store(summary.blocked_queries, Ordering::Relaxed);

        // The top lists have to be adopted too, not just the counters: on iOS
        // the extension does all the filtering, so the app process counts
        // nothing of its own and would otherwise render an empty analytics
        // screen next to a populated one. Replacing rather than merging is
        // deliberate — the snapshot is the whole truth about what the tunnel
        // saw, and adding to stale local entries would double-count.
        let adopt = |counts: &RwLock<HashMap<String, u64>>, top: &[DomainCount]| {
            let mut counts = counts.write().unwrap();
            counts.clear();
            for entry in top {
                counts.insert(entry.domain.clone(), entry.count);
            }
        };

        adopt(&self.blocked_counts, &summary.top_blocked);
        adopt(&self.allowed_counts, &summary.top_allowed);

        let mut apps = self.app_counts.write().unwrap();
        apps.clear();
        for app in &summary.top_apps {
            apps.insert(
                app.uid,
                AppTally {
                    total: app.total,
                    blocked: app.blocked,
                },
            );
        }
    }

    pub fn get_recent_logs(&self, limit: usize) -> Vec<DnsLogEntry> {
        let logs = self.logs.read().unwrap();
        logs.iter().take(limit).cloned().collect()
    }

    pub fn reset(&self) {
        self.total_queries.store(0, Ordering::Relaxed);
        self.blocked_queries.store(0, Ordering::Relaxed);
        self.logs.write().unwrap().clear();
        self.blocked_counts.write().unwrap().clear();
        self.allowed_counts.write().unwrap().clear();
        self.app_counts.write().unwrap().clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn top_lists_rank_by_hit_count() {
        let stats = StatisticsEngine::new(64);
        for _ in 0..5 {
            stats.record_request("ads.example.com", true);
        }
        for _ in 0..2 {
            stats.record_request("tracker.example.com", true);
        }
        stats.record_request("cdn.example.com", false);

        let summary = stats.get_summary();
        assert_eq!(summary.top_blocked[0].domain, "ads.example.com");
        assert_eq!(summary.top_blocked[0].count, 5);
        assert_eq!(summary.top_blocked[1].domain, "tracker.example.com");
        assert_eq!(summary.top_allowed[0].domain, "cdn.example.com");
    }

    #[test]
    fn top_lists_report_at_most_five_domains() {
        let stats = StatisticsEngine::new(64);
        for i in 0..50 {
            stats.record_request(&format!("host{}.example.com", i), true);
        }
        assert_eq!(stats.get_summary().top_blocked.len(), TOP_DOMAIN_COUNT);
    }

    #[test]
    fn domain_table_stays_bounded_under_a_flood_of_unique_names() {
        // A device resolving a new hostname every query must not grow this
        // table without limit; before the cap it kept every name forever.
        let stats = StatisticsEngine::new(64);
        for i in 0..(MAX_TRACKED_DOMAINS * 3) {
            stats.record_request(&format!("host{}.example.com", i), false);
        }

        let tracked = stats.allowed_counts.read().unwrap().len();
        assert!(
            tracked <= MAX_TRACKED_DOMAINS,
            "table grew to {} entries, past the {} cap",
            tracked,
            MAX_TRACKED_DOMAINS
        );
    }

    #[test]
    fn eviction_keeps_the_busiest_domains() {
        let stats = StatisticsEngine::new(64);

        // A domain that is actually busy has to survive the flood of
        // one-hit names that triggers eviction, or the top-5 is worthless.
        for _ in 0..100 {
            stats.record_request("busy.example.com", true);
        }
        for i in 0..(MAX_TRACKED_DOMAINS * 2) {
            stats.record_request(&format!("once{}.example.com", i), true);
        }

        let summary = stats.get_summary();
        assert_eq!(summary.top_blocked[0].domain, "busy.example.com");
        assert_eq!(summary.top_blocked[0].count, 100);
    }

    #[test]
    fn adopted_summary_carries_the_top_lists_across_the_process_boundary() {
        // On iOS the app process filters nothing, so without this its
        // analytics screen would sit empty while the tunnel's is full.
        let tunnel = StatisticsEngine::new(64);
        for _ in 0..3 {
            tunnel.record_request("ads.example.com", true);
        }

        let app = StatisticsEngine::new(64);
        app.apply_summary(&tunnel.get_summary());

        let summary = app.get_summary();
        assert_eq!(summary.total_queries, 3);
        assert_eq!(summary.top_blocked[0].domain, "ads.example.com");
        assert_eq!(summary.top_blocked[0].count, 3);
    }
    #[test]
    fn app_tallies_rank_by_total_and_count_blocked_queries() {
        let stats = StatisticsEngine::new(64);
        for _ in 0..3 {
            stats.record_request_for_uid("ads.example.com", true, 10_123);
        }
        stats.record_request_for_uid("cdn.example.com", false, 10_123);
        stats.record_request_for_uid("cdn.example.com", false, 10_456);

        let apps = stats.get_summary().top_apps;
        assert_eq!(apps[0].uid, 10_123);
        assert_eq!(apps[0].total, 4);
        assert_eq!(apps[0].blocked, 3);
        assert_eq!(apps[1].uid, 10_456);
        assert_eq!(apps[1].blocked, 0);
    }

    #[test]
    fn requests_without_an_app_count_under_the_unknown_uid() {
        let stats = StatisticsEngine::new(64);
        stats.record_request("example.com", false);

        let apps = stats.get_summary().top_apps;
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0].uid, UNKNOWN_UID);
        assert_eq!(stats.get_recent_logs(1)[0].uid, UNKNOWN_UID);
    }

    #[test]
    fn log_entries_carry_the_uid() {
        let stats = StatisticsEngine::new(64);
        stats.record_request_for_uid("example.com", false, 10_200);
        assert_eq!(stats.get_recent_logs(1)[0].uid, 10_200);
    }

    #[test]
    fn top_apps_lists_at_most_twenty() {
        let stats = StatisticsEngine::new(64);
        for uid in 0..50 {
            stats.record_request_for_uid("example.com", false, 10_000 + uid);
        }
        assert_eq!(stats.get_summary().top_apps.len(), TOP_APP_COUNT);
    }

    #[test]
    fn app_table_stays_bounded_and_keeps_busy_apps() {
        let stats = StatisticsEngine::new(64);
        for _ in 0..100 {
            stats.record_request_for_uid("example.com", true, 10_001);
        }
        for uid in 0..(MAX_TRACKED_APPS as i32 * 3) {
            stats.record_request_for_uid("example.com", false, 20_000 + uid);
        }

        assert!(stats.app_counts.read().unwrap().len() <= MAX_TRACKED_APPS);
        let apps = stats.get_summary().top_apps;
        assert_eq!(apps[0].uid, 10_001);
        assert_eq!(apps[0].total, 100);
    }

    #[test]
    fn reset_clears_app_tallies() {
        let stats = StatisticsEngine::new(64);
        stats.record_request_for_uid("example.com", false, 10_123);
        stats.reset();
        assert!(stats.get_summary().top_apps.is_empty());
    }

    #[test]
    fn adopted_summary_carries_top_apps() {
        let tunnel = StatisticsEngine::new(64);
        tunnel.record_request_for_uid("ads.example.com", true, 10_123);

        let app = StatisticsEngine::new(64);
        app.apply_summary(&tunnel.get_summary());

        let apps = app.get_summary().top_apps;
        assert_eq!(apps[0].uid, 10_123);
        assert_eq!(apps[0].blocked, 1);
    }

    #[test]
    fn json_from_before_per_app_stats_still_parses() {
        // iOS snapshots written by 1.3.0 have neither field.
        let summary: StatsSummary = serde_json::from_str(
            r#"{"total_queries":1,"blocked_queries":0,"allowed_queries":1,
                "block_rate_percentage":0.0,"estimated_data_saved_bytes":0,
                "top_blocked":[],"top_allowed":[]}"#,
        )
        .expect("old summary");
        assert!(summary.top_apps.is_empty());

        let entry: DnsLogEntry = serde_json::from_str(
            r#"{"id":1,"timestamp":0,"domain":"example.com","blocked":false}"#,
        )
        .expect("old log entry");
        assert_eq!(entry.uid, UNKNOWN_UID);
    }
}
