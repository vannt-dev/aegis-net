//! Snapshots that move engine state between processes.
//!
//! On Android the VPN service and the UI share one process, so this module is
//! unused there. On iOS the app (Runner) and the tunnel (PacketTunnel
//! extension) are separate processes with separate copies of the engine, and
//! they exchange state through files in the shared App Group container.
//!
//! The format lives here rather than in Swift on purpose: both processes go
//! through the same code, and the round trip is testable without a Mac.

use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::dns_filter::DnsFilterService;
use crate::rule_engine::{RuleCategory, RuleEngine};
use crate::statistics::{StatisticsEngine, StatsSummary};

/// Bumped when the snapshot layout changes. A reader that sees a version it
/// does not know refuses the file instead of guessing at the contents.
pub const SNAPSHOT_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SettingsSnapshot {
    pub version: u32,
    pub enabled_categories: Vec<RuleCategory>,
    pub whitelist: Vec<String>,
    pub blacklist: Vec<String>,
    pub upstream_dns: String,
}

#[derive(Debug)]
pub enum SnapshotError {
    Io,
    Malformed,
    UnsupportedVersion,
}

impl SnapshotError {
    /// Negative status codes for the C ABI; `0` means success there.
    pub fn code(&self) -> i32 {
        match self {
            SnapshotError::Io => -1,
            SnapshotError::Malformed => -2,
            SnapshotError::UnsupportedVersion => -3,
        }
    }
}

pub fn settings_snapshot(engine: &RuleEngine, filter: &DnsFilterService) -> SettingsSnapshot {
    SettingsSnapshot {
        version: SNAPSHOT_VERSION,
        enabled_categories: engine.enabled_categories(),
        whitelist: engine.whitelist(),
        blacklist: engine.blacklist(),
        upstream_dns: filter.upstream_dns(),
    }
}

pub fn export_settings(
    engine: &RuleEngine,
    filter: &DnsFilterService,
    path: &Path,
) -> Result<(), SnapshotError> {
    let snapshot = settings_snapshot(engine, filter);
    let json = serde_json::to_string(&snapshot).map_err(|_| SnapshotError::Malformed)?;
    write_atomically(path, json.as_bytes())
}

pub fn import_settings(
    engine: &RuleEngine,
    filter: &DnsFilterService,
    path: &Path,
) -> Result<(), SnapshotError> {
    let json = fs::read_to_string(path).map_err(|_| SnapshotError::Io)?;
    let snapshot: SettingsSnapshot =
        serde_json::from_str(&json).map_err(|_| SnapshotError::Malformed)?;

    if snapshot.version != SNAPSHOT_VERSION {
        return Err(SnapshotError::UnsupportedVersion);
    }

    engine.replace_user_state(
        &snapshot.enabled_categories,
        &snapshot.whitelist,
        &snapshot.blacklist,
    );
    filter.set_upstream_dns(&snapshot.upstream_dns);
    Ok(())
}

/// Load a downloaded filter list straight off disk. Filter lists run to
/// hundreds of thousands of lines, so they stay as their original text and are
/// never folded into the JSON snapshot.
pub fn load_rules_file(
    engine: &RuleEngine,
    path: &Path,
    category: RuleCategory,
) -> Result<usize, SnapshotError> {
    let content = fs::read_to_string(path).map_err(|_| SnapshotError::Io)?;
    Ok(engine.load_rules_text(&content, category))
}

pub fn export_stats(stats: &StatisticsEngine, path: &Path) -> Result<(), SnapshotError> {
    let json = serde_json::to_string(&stats.get_summary()).map_err(|_| SnapshotError::Malformed)?;
    write_atomically(path, json.as_bytes())
}

pub fn import_stats(stats: &StatisticsEngine, path: &Path) -> Result<(), SnapshotError> {
    let json = fs::read_to_string(path).map_err(|_| SnapshotError::Io)?;
    let summary: StatsSummary =
        serde_json::from_str(&json).map_err(|_| SnapshotError::Malformed)?;
    stats.apply_summary(&summary);
    Ok(())
}

/// Write to a sibling temp file and rename over the target. The reader is a
/// different process that can wake up at any moment, and a rename is atomic, so
/// it never observes a half-written snapshot.
fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), SnapshotError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|_| SnapshotError::Io)?;
    }

    let temp_path = path.with_extension("tmp");
    fs::write(&temp_path, bytes).map_err(|_| SnapshotError::Io)?;
    fs::rename(&temp_path, path).map_err(|_| SnapshotError::Io)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn temp_path(name: &str) -> std::path::PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "aegis_shared_state_{}_{}",
            std::process::id(),
            name
        ));
        path
    }

    fn engine_pair() -> (Arc<RuleEngine>, DnsFilterService) {
        let engine = Arc::new(RuleEngine::new());
        let stats = Arc::new(StatisticsEngine::new(16));
        let filter = DnsFilterService::new(
            engine.clone(),
            stats,
            "https://1.1.1.1/dns-query".to_string(),
        );
        (engine, filter)
    }

    #[test]
    fn settings_round_trip_preserves_blocking_decisions() {
        let path = temp_path("round_trip.json");
        let _ = fs::remove_file(&path);

        // Producer side: the app, configured by the user.
        let (app_engine, app_filter) = engine_pair();
        app_engine.set_category_enabled(RuleCategory::Trackers, false);
        app_engine.set_category_enabled(RuleCategory::Adult, true);
        app_engine.add_whitelist("Doubleclick.NET");
        app_engine.add_blacklist("example-tracker.com");
        app_filter.set_upstream_dns("https://dns.google/dns-query");
        export_settings(&app_engine, &app_filter, &path).expect("export");

        // Consumer side: a fresh engine, as the extension starts out.
        let (ext_engine, ext_filter) = engine_pair();
        assert!(ext_engine.is_blocked("doubleclick.net"));
        assert!(ext_engine.is_blocked("graph.facebook.com"));

        import_settings(&ext_engine, &ext_filter, &path).expect("import");

        // Whitelisted in the app, so no longer blocked here. Case is normalised.
        assert!(!ext_engine.is_blocked("doubleclick.net"));
        // Trackers were disabled in the app.
        assert!(!ext_engine.is_blocked("graph.facebook.com"));
        // Blacklisted in the app.
        assert!(ext_engine.is_blocked("example-tracker.com"));
        assert_eq!(ext_filter.upstream_dns(), "https://dns.google/dns-query");

        // And the snapshots now agree.
        assert_eq!(
            settings_snapshot(&app_engine, &app_filter),
            settings_snapshot(&ext_engine, &ext_filter)
        );

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn import_removes_entries_absent_from_the_snapshot() {
        let path = temp_path("removal.json");
        let _ = fs::remove_file(&path);

        let (app_engine, app_filter) = engine_pair();
        export_settings(&app_engine, &app_filter, &path).expect("export");

        // The consumer holds a stale entry the producer never had.
        let (ext_engine, ext_filter) = engine_pair();
        ext_engine.add_blacklist("stale-rule.com");
        assert!(ext_engine.is_blocked("stale-rule.com"));

        import_settings(&ext_engine, &ext_filter, &path).expect("import");

        assert!(!ext_engine.is_blocked("stale-rule.com"));
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn missing_and_corrupt_snapshots_are_errors_not_panics() {
        let (engine, filter) = engine_pair();

        let missing = temp_path("does_not_exist.json");
        let _ = fs::remove_file(&missing);
        assert_eq!(
            import_settings(&engine, &filter, &missing)
                .unwrap_err()
                .code(),
            -1
        );

        let corrupt = temp_path("corrupt.json");
        fs::write(&corrupt, b"{ not json").expect("write");
        assert_eq!(
            import_settings(&engine, &filter, &corrupt)
                .unwrap_err()
                .code(),
            -2
        );

        let wrong_version = temp_path("version.json");
        fs::write(
            &wrong_version,
            br#"{"version":999,"enabled_categories":[],"whitelist":[],"blacklist":[],"upstream_dns":"x"}"#,
        )
        .expect("write");
        assert_eq!(
            import_settings(&engine, &filter, &wrong_version)
                .unwrap_err()
                .code(),
            -3
        );

        // A refused snapshot must leave the engine untouched.
        assert!(engine.is_blocked("doubleclick.net"));

        let _ = fs::remove_file(&corrupt);
        let _ = fs::remove_file(&wrong_version);
    }

    #[test]
    fn rules_load_from_a_file_like_they_do_from_text() {
        let path = temp_path("rules.txt");
        fs::write(
            &path,
            "# comment\n0.0.0.0 ads.example.com\nmalware.example.org\n",
        )
        .expect("write");

        let (engine, _filter) = engine_pair();
        assert!(!engine.is_blocked("ads.example.com"));

        let added = load_rules_file(&engine, &path, RuleCategory::Ads).expect("load");

        assert_eq!(added, 2);
        assert!(engine.is_blocked("ads.example.com"));
        assert!(engine.is_blocked("sub.ads.example.com"));

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn stats_cross_the_process_boundary() {
        let path = temp_path("stats.json");
        let _ = fs::remove_file(&path);

        // The extension is the only side that sees real traffic.
        let tunnel_stats = StatisticsEngine::new(16);
        tunnel_stats.record_request("ads.example.com", true);
        tunnel_stats.record_request("github.com", false);
        tunnel_stats.record_request("tracker.example.net", true);
        export_stats(&tunnel_stats, &path).expect("export");

        let app_stats = StatisticsEngine::new(16);
        assert_eq!(app_stats.get_summary().total_queries, 0);

        import_stats(&app_stats, &path).expect("import");

        let summary = app_stats.get_summary();
        assert_eq!(summary.total_queries, 3);
        assert_eq!(summary.blocked_queries, 2);
        assert_eq!(summary.allowed_queries, 1);

        let _ = fs::remove_file(&path);
    }
}
