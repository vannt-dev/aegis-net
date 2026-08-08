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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainCount {
    pub domain: String,
    pub count: u64,
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
}

pub struct StatisticsEngine {
    total_queries: AtomicU64,
    blocked_queries: AtomicU64,
    logs: RwLock<VecDeque<DnsLogEntry>>,
    blocked_counts: RwLock<HashMap<String, u64>>,
    allowed_counts: RwLock<HashMap<String, u64>>,
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
            max_log_capacity,
            counter_id: AtomicU64::new(1),
        }
    }

    pub fn record_request(&self, domain: &str, blocked: bool) {
        self.total_queries.fetch_add(1, Ordering::Relaxed);
        let domain_str = domain.to_string();

        if blocked {
            self.blocked_queries.fetch_add(1, Ordering::Relaxed);
            let mut counts = self.blocked_counts.write().unwrap();
            *counts.entry(domain_str.clone()).or_insert(0) += 1;
        } else {
            let mut counts = self.allowed_counts.write().unwrap();
            *counts.entry(domain_str.clone()).or_insert(0) += 1;
        }

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
        };

        let mut logs = self.logs.write().unwrap();
        if logs.len() >= self.max_log_capacity {
            logs.pop_back();
        }
        logs.push_front(entry);
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

        let get_top = |counts_lock: &RwLock<HashMap<String, u64>>| -> Vec<DomainCount> {
            let counts = counts_lock.read().unwrap();
            let mut items: Vec<(String, u64)> =
                counts.iter().map(|(k, v)| (k.clone(), *v)).collect();
            items.sort_by(|a, b| b.1.cmp(&a.1));
            items
                .into_iter()
                .take(5)
                .map(|(d, c)| DomainCount {
                    domain: d,
                    count: c,
                })
                .collect()
        };

        let top_blocked = get_top(&self.blocked_counts);
        let top_allowed = get_top(&self.allowed_counts);

        StatsSummary {
            total_queries: total,
            blocked_queries: blocked,
            allowed_queries: allowed,
            block_rate_percentage: block_rate,
            estimated_data_saved_bytes: data_saved,
            top_blocked,
            top_allowed,
        }
    }

    /// Adopt counters produced by another process (the iOS PacketTunnel
    /// extension). Only the counters cross the boundary; the log ring stays
    /// local, since it is display-only and would bloat the snapshot.
    pub fn apply_summary(&self, summary: &StatsSummary) {
        self.total_queries
            .store(summary.total_queries, Ordering::Relaxed);
        self.blocked_queries
            .store(summary.blocked_queries, Ordering::Relaxed);
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
    }
}
