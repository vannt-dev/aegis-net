use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::RwLock;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DnsLogEntry {
    pub id: u64,
    pub timestamp: u64,
    pub domain: String,
    pub blocked: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatsSummary {
    pub total_queries: u64,
    pub blocked_queries: u64,
    pub allowed_queries: u64,
    pub block_rate_percentage: f64,
    pub estimated_data_saved_bytes: u64,
}

pub struct StatisticsEngine {
    total_queries: AtomicU64,
    blocked_queries: AtomicU64,
    logs: RwLock<VecDeque<DnsLogEntry>>,
    max_log_capacity: usize,
    counter_id: AtomicU64,
}

impl StatisticsEngine {
    pub fn new(max_log_capacity: usize) -> Self {
        Self {
            total_queries: AtomicU64::new(0),
            blocked_queries: AtomicU64::new(0),
            logs: RwLock::new(VecDeque::with_capacity(max_log_capacity)),
            max_log_capacity,
            counter_id: AtomicU64::new(1),
        }
    }

    pub fn record_request(&self, domain: &str, blocked: bool) {
        self.total_queries.fetch_add(1, Ordering::Relaxed);
        if blocked {
            self.blocked_queries.fetch_add(1, Ordering::Relaxed);
        }

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let id = self.counter_id.fetch_add(1, Ordering::Relaxed);

        let entry = DnsLogEntry {
            id,
            timestamp,
            domain: domain.to_string(),
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

        StatsSummary {
            total_queries: total,
            blocked_queries: blocked,
            allowed_queries: allowed,
            block_rate_percentage: block_rate,
            estimated_data_saved_bytes: data_saved,
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
    }
}
