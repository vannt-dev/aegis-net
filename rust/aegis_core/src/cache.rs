use dashmap::DashMap;
use std::time::{Duration, Instant};

#[derive(Clone)]
pub struct CachedDnsRecord {
    pub payload: Vec<u8>,
    pub expires_at: Instant,
}

pub struct DnsCache {
    cache: DashMap<String, CachedDnsRecord>,
    default_ttl: Duration,
}

impl DnsCache {
    pub fn new(ttl_seconds: u64) -> Self {
        Self {
            cache: DashMap::new(),
            default_ttl: Duration::from_secs(ttl_seconds),
        }
    }

    /// Retrieve valid non-expired DNS payload from cache
    pub fn get(&self, domain: &str) -> Option<Vec<u8>> {
        if let Some(entry) = self.cache.get(domain) {
            if Instant::now() < entry.expires_at {
                return Some(entry.payload.clone());
            }
        }
        None
    }

    /// Insert DNS payload into cache with TTL
    pub fn insert(&self, domain: String, payload: Vec<u8>) {
        let expires_at = Instant::now() + self.default_ttl;
        self.cache.insert(
            domain,
            CachedDnsRecord {
                payload,
                expires_at,
            },
        );
    }

    /// Clear all cached entries
    pub fn clear(&self) {
        self.cache.clear();
    }
}
