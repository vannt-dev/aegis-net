//! Measure what a candidate filter list would actually buy us, and what it
//! costs in the trie.
//!
//! Two numbers decide whether a list belongs in `defaultSources`: how many
//! domains it blocks that the current set does *not* already cover, and how
//! much memory it adds. Memory is the binding constraint — the iOS
//! PacketTunnel extension has a hard limit in the tens of MB, and every list
//! in the defaults is enabled for every user.
//!
//! Run with `cargo run --release --example probe` (needs network). To weigh a
//! new list, add it to `CANDIDATES`.
//!
//! Classification goes through `RuleEngine::parse_line`, the same call
//! `load_rules_text` uses, so the counts here cannot drift from what the app
//! would really load.

use aegis_core::rule_engine::{DomainTrie, LineKind, RuleEngine};
use std::alloc::{GlobalAlloc, Layout, System};
use std::collections::HashSet;
use std::io::Read;
use std::sync::atomic::{AtomicUsize, Ordering};

/// Counts live bytes so a trie can be weighed directly, rather than inferred
/// from a per-node estimate that would go stale the moment `TrieNode` changes.
struct Counting;
static LIVE: AtomicUsize = AtomicUsize::new(0);

unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        LIVE.fetch_add(l.size(), Ordering::Relaxed);
        System.alloc(l)
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        LIVE.fetch_sub(l.size(), Ordering::Relaxed);
        System.dealloc(p, l)
    }
}

#[global_allocator]
static A: Counting = Counting;

/// The lists currently in `RuleDownloaderService.defaultSources`.
const CURRENT: [(&str, &str); 4] = [
    (
        "AdGuard DNS",
        "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt",
    ),
    (
        "StevenBlack",
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
    ),
    (
        "Peter Lowe",
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext",
    ),
    ("OISD Small", "https://small.oisd.nl/"),
];

/// Lists being weighed for inclusion.
const CANDIDATES: [(&str, &str); 1] = [("OISD Big", "https://big.oisd.nl/")];

struct Tally {
    blocked: HashSet<String>,
    allowed: usize,
    unusable: usize,
    bytes: usize,
}

fn fetch(url: &str) -> Option<(String, usize)> {
    let mut body = String::new();
    let resp = ureq::get(url)
        .timeout(std::time::Duration::from_secs(180))
        .call()
        .ok()?;
    resp.into_reader()
        .take(200_000_000)
        .read_to_string(&mut body)
        .ok()?;
    let bytes = body.len();
    Some((body, bytes))
}

fn tally(text: &str, bytes: usize) -> Tally {
    let mut t = Tally {
        blocked: HashSet::new(),
        allowed: 0,
        unusable: 0,
        bytes,
    };
    for line in text.lines() {
        match RuleEngine::parse_line(line) {
            LineKind::Block(domain) => {
                t.blocked.insert(domain);
            }
            LineKind::Allow(_) => t.allowed += 1,
            LineKind::Unusable => t.unusable += 1,
            LineKind::Comment => {}
        }
    }
    t
}

/// Build a trie from `domains` and report what it cost, in MB.
fn trie_mb(domains: &HashSet<String>) -> f64 {
    let base = LIVE.load(Ordering::Relaxed);
    let mut trie = DomainTrie::new();
    for d in domains {
        trie.insert(d);
    }
    trie.shrink_to_fit();
    let used = LIVE.load(Ordering::Relaxed) - base;
    // Keep the trie alive past the measurement, or the allocator sees the
    // frees and reports roughly nothing.
    assert!(trie.len() > 0);
    used as f64 / 1_048_576.0
}

fn main() {
    let mut baseline: HashSet<String> = HashSet::new();

    println!("=== current defaults ===");
    for (name, url) in CURRENT {
        match fetch(url) {
            Some((text, bytes)) => {
                let t = tally(&text, bytes);
                println!(
                    "  {:<12} {:>7} blocked, {:>4} allow, {:>5} unusable, {:>5.1} MB download",
                    name,
                    t.blocked.len(),
                    t.allowed,
                    t.unusable,
                    t.bytes as f64 / 1e6
                );
                baseline.extend(t.blocked);
            }
            None => println!("  {:<12} DOWNLOAD FAILED", name),
        }
    }

    let base_mb = trie_mb(&baseline);
    println!(
        "  --> merged   {:>7} domains, trie {:.1} MB",
        baseline.len(),
        base_mb
    );

    println!("\n=== candidates ===");
    for (name, url) in CANDIDATES {
        let Some((text, bytes)) = fetch(url) else {
            println!("  {:<12} DOWNLOAD FAILED", name);
            continue;
        };
        let t = tally(&text, bytes);
        let new = t.blocked.difference(&baseline).count();
        let mut merged = baseline.clone();
        merged.extend(t.blocked.iter().cloned());
        let merged_mb = trie_mb(&merged);
        let covered = t.blocked.len() - new;

        println!("\n  {}", name);
        println!(
            "    blocked domains  : {:>7}   ({} allow, {} unusable, {:.1} MB download)",
            t.blocked.len(),
            t.allowed,
            t.unusable,
            t.bytes as f64 / 1e6
        );
        println!(
            "    already covered  : {:>7}   ({:.1}%)",
            covered,
            covered as f64 * 100.0 / t.blocked.len() as f64
        );
        println!("    NEWLY BLOCKED    : {:>7}", new);
        println!(
            "    trie once merged : {:.1} MB  (+{:.1} MB over {:.1})",
            merged_mb,
            merged_mb - base_mb,
            base_mb
        );
    }
}
