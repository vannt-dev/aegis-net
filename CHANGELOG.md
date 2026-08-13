# 📓 Changelog

All notable engineering changes to **AegisNet**. This log records the work that
turned the app from a UI shell with mocked data into a working DNS filter with a
verified native pipeline on Android.

## [Unreleased]

### 🐛 YouTube would not load with the tunnel on

- **`youtubei.googleapis.com` was blocked by default, which breaks the YouTube
  app outright.** It is not a tracker: it is YouTube's InnerTube API, the one
  the app fetches its home feed, its search results and the player config
  carrying the stream URLs from. Blocked, the app renders its skeleton and
  nothing ever fills it in — no thumbnails, no playback. Reported on Realme /
  Android 14, but nothing about it was device-specific.

  The rule came from `seed_default_rules()`, a built-in list that applies
  before any filter list is downloaded, in the Trackers category, which is on
  by default. So it hit every user from the first launch, and no setting on
  screen explained why.

- **`graph.facebook.com` removed for the same reason** — the Facebook Graph
  API, which every app offering Facebook login depends on.
- Genuine telemetry stays blocked: `s.youtube.com` and
  `video-stats.l.google.com` are playback statistics, and YouTube works fine
  without them.
- `test_seed_rules_never_block_an_app_s_own_api` now guards the seed list, and
  the comment above it says what the list is allowed to contain.

### 🧹 Filter rule parsing

- **Rules that could never match are no longer stored.** The parser ended in a
  catch-all — any line with a dot and no space became a "domain" — so filter
  syntax the DNS matcher cannot express was kept verbatim. Measured against the
  lists actually shipped: **669 such entries in the AdGuard DNS filter**, and
  17,779 in EasyList. Each one occupied memory, inflated the "rules loaded"
  count shown to the user, and matched nothing.

  | | AdGuard DNS | StevenBlack | Peter Lowe |
  |---|---|---|---|
  | unusable entries before | 669 | 0 | 0 |
  | after | **0** | 0 | 0 |

- **`||domain` without a trailing `^` now loads.** 172 rules in the AdGuard DNS
  filter are written that way. They fell through to the catch-all and were
  stored with the `||` still attached, so those domains were **never actually
  blocked** while the UI counted them as active rules. The same fix applies to
  `@@||domain` exceptions.
- Wildcards (`||ads.livetv*.me^`), regex, path-scoped and resource-type rules
  are now dropped deliberately rather than stored as garbage. A DNS filter sees
  a hostname and nothing else; none of these can be honoured.
- **Added Peter Lowe's Ad and Tracking Server List** to the default sources.
  Hostname-only, so every line survives the DNS parser — 3,525 rules, zero
  unusable. It is one of the lists uBlock Origin Lite enables by default.
- **Added OISD Small** to the default sources, and deliberately not OISD Big.
  Measured against the lists already shipped, with memory as the deciding
  factor — the iOS PacketTunnel extension has a hard limit in the tens of MB,
  and the merged trie already costs 18.3 MB before either list is added.

  | | domains | already covered | newly blocked | trie cost |
  |---|---|---|---|---|
  | OISD Small | 56,747 | 93.5% | **3,673** | **+0.2 MB** |
  | OISD Big | 265,831 | 32.3% | 179,917 | +11.1 MB |

  OISD Big blocks a great deal more, but 11.1 MB on top of 18.3 MB is not a
  trade the extension can make, and every list in the defaults is enabled for
  every user. It can still be added by hand as a custom source.

## [1.1.0] — 2026-08-12

Android is verified on an Android 14 emulator: the tunnel establishes, a blocked
domain answers NXDOMAIN (`ping doubleclick.net` → unknown host), a normal domain
resolves through the DoH upstream (`ping example.com` → 172.66.147.243), and the
dashboard shows the engine's own counters. **iOS is not verified** — the
PacketTunnel target was only just added and none of its Swift has been compiled
on a Mac yet. Treat this release as Android-only.

### 🚨 Fixed — release blockers found by review

- **The Android tunnel could not start at all.** The IPv6 ULA was written
  `fd00:aegis::2`, which is not a valid IPv6 literal (`g`, `i` and `s` are not
  hex digits), so `VpnService.Builder.addAddress` threw before `establish()` was
  ever reached.
- **DNS failed outright with the default upstream.** Routing public resolver IPs
  (1.1.1.1, 8.8.8.8, 9.9.9.9, …) into the TUN to stop apps bypassing the filter
  also captured the engine's *own* DoH traffic to `https://1.1.1.1/dns-query`,
  where the DNS-only filter dropped it. Every lookup ended in SERVFAIL after a
  5s timeout. The routes are removed; doing this properly needs a protected
  upstream socket and is tracked in ROADMAP.md.
- **Quick Settings tile crashed on Android 14+.** `startActivityAndCollapse(Intent)`
  throws `UnsupportedOperationException` for apps targeting API 34, and the app
  targets 36.
- **Quick Settings tile crashed on Android 12+.** Tapping it with the app closed
  called `startForegroundService` from the background, which is not an exempt
  context for a tile click; the resulting `ForegroundServiceStartNotAllowedException`
  went uncaught. It now falls back to opening the app.
- **The service came back as a zombie after being killed.** `START_STICKY`
  redelivers a null intent, which matched no branch, leaving the process alive
  with no notification and no tunnel — the routine outcome on MIUI. It now
  rebuilds the tunnel, using a bypass list persisted to storage so a process
  kill does not silently route the user's excluded apps through the VPN.
- **The tile reported stale state.** It kept showing "ON" after the tunnel went
  down, including after MIUI revoked VPN consent.

### 🌲 Rust Core Engine — DomainTrie Optimization & Custom Hosts

- **DomainTrie prefix tree.** Replaced `HashSet<String>` domain matching with a
  `DomainTrie` that stores one node per label, so a blocked zone costs one
  terminal node instead of one entry per host. Note the behaviour change: the
  user denylist now covers subdomains, where it used to match exact hosts only.
- **DomainTrie memory fix.** The first version gave each node a
  `HashMap<String, TrieNode>`, which measured at **2.5x–7.7x the memory of the
  `HashSet` it replaced** — the opposite of the intended effect, because a
  domain trie is mostly single-child chains and every one of them paid for a
  hash table. Children are now a sorted `Vec<(Box<str>, TrieNode)>` searched by
  binary search. Measured over 300k rules with a counting allocator:

  | Rule shape | Before | After | `HashSet` baseline |
  |---|---|---|---|
  | 2-label, hosts-style | 44.4 MB | 17.6 MB | 17.5 MB |
  | 3-label, unique second level | 142.2 MB | 31.9 MB | 18.4 MB |
  | Many subdomains under 500 zones | 41.5 MB | 15.7 MB | 17.8 MB |

  This is what made it a correctness issue rather than a tuning one: the iOS
  PacketTunnel extension has a hard memory limit in the tens of MB, and the
  default blocklists are large enough that the old layout got it killed.
  Lookups are ~170 ns, so no speed claim is made either way — the trie's win is
  that one rule covers a whole zone.
- **Custom DNS Host Overrides (Local DNS Mapping).** Added local DNS mapping
  support (`domain` -> `IP`, e.g. `myrouter.local` -> `192.168.1.1`) directly in
  the Rust engine, with C-FFI exports `aegis_add_custom_host` and
  `aegis_remove_custom_host`. Overrides answer A and AAAA with a record of the
  matching family and NOERROR/empty otherwise, and travel in the settings
  snapshot so the iOS extension honours them too.
- **Bounded top-domain statistics.** The per-domain hit counters are capped at
  2,000 names per direction, evicting the coldest half when full, and the top-5
  is selected linearly instead of sorting and cloning the whole table on every
  UI poll.

### 🧹 Removed — numbers the UI invented

Several screens filled empty state with realistic-looking sample data, which is
indistinguishable from a measurement once it is rendered. All of it is gone; the
screens now say they have no data yet.

- Dashboard opened at 1,420 queries / 385 blocked / 27.1% / 55.1 MB on a fresh
  install, and the query log came pre-seeded with three fabricated entries.
- Analytics fell back to a hand-written top-blocked list (`doubleclick.net`
  ×142, `api.github.com` ×320, …) whenever the engine had counted nothing.
- "Hourly Query Distribution" drew seven hardcoded bars that never changed.
  There is no hourly bucketing to plot, so the chart now shows the query-rate
  history that does exist, retitled to match.
- The dashboard's "Traffic & Latency" curve was seeded with
  `[15, 28, 42, 35, 50, 48, 62]`, drawing convincing traffic on a device that
  had never resolved anything, next to a hardcoded "14 ms (Ultra Fast)" that
  was never measured — the engine does not time its lookups. The chart starts
  empty and the badge reports the sample count instead.
- Settings had an "Export / Import Configuration" button that built a JSON
  string, discarded it, and reported "Config exported successfully: N bytes".
  Removed — the Backup & Restore section does the real thing.

### 🔢 Versioning

- The settings footer hardcoded `v1.0.0` with nothing keeping it honest. It now
  reads `kAppVersion`, and a test asserts that constant matches `pubspec.yaml`
  — the release workflow runs the test before it builds.

### 💻 Desktop Scaffolding & Desktop DNS Proxy

- **Multi-Platform Desktop Shell.** Added native desktop scaffolding
  (`windows/`, `macos/`, `linux/`) so the app compiles and runs as a native
  desktop application.
- **Desktop DNS Resolver Integration.** Connected `DesktopDnsProxy` through
  `AegisBridge` and `VpnProvider` for desktop platforms.

### ⏰ Quiet Hours Schedule Blocking & Custom Subscriptions

- **Scheduled Parental Control.** Added `setSchedule` and quiet hours
  evaluation (default 22:00 - 06:00) to automatically enforce Adult category
  filters during quiet hours.
- **Custom Hosts UI Tab.** Added a dedicated **Local DNS Hosts** tab in
  `RulesScreen` for managing local DNS host overrides with real-time UI mapping.
- **Status Filter Chips in Logs.** Added `ALL LOGS`, `BLOCKED`, and `ALLOWED`
  filter chips in `LogsScreen` for fast real-time query log inspection.
- **Full Configuration Backup.** Extended `ConfigSyncService` JSON
  export/import to backup custom hosts, schedule settings, and custom filter
  sources.
- **Expanded Test Coverage.** Rust tests: **16 → 33**, Flutter unit & widget
  tests: **7 → 28**.

### 🔴 Android — Real DNS filtering (verified on device)

- **Native TUN → Rust → device pipeline wired end-to-end.** `AegisVpnService`
  now reads each IPv4 packet off the TUN, hands it to the Rust engine
  (`aegis_process_ip_packet` via a JNI bridge), and writes synthesized DNS
  replies back. Previously the read loop discarded every packet.
- **DNS-only tunnel routing.** Only the virtual DNS server (`10.0.0.3/32`) is
  routed into the TUN. Non-DNS traffic and the engine's own upstream lookups
  stay on the real network, so nothing loops and no `VpnService.protect()` is
  required.
- **Graceful native-absent fallback / crash fix.** `System.loadLibrary` ran in
  the service's static initializer and crashed the whole app on VPN start when
  `libaegis_core.so` was not bundled. It is now loaded defensively behind a
  `nativeAvailable` flag; the app falls back to simulation instead of crashing.
- **Reproducible native build.** A best-effort Gradle `preBuild` task compiles
  the Rust engine with `cargo-ndk` into `jniLibs` for all ABIs. It runs only
  when `cargo-ndk` is on `PATH`, so toolchain-less machines still build.

  > **Verified on an Android 34 emulator:** `doubleclick.net` and
  > `graph.facebook.com` resolve to a null address (blocked) while `github.com`
  > resolves to its real IP via DoH.

### 🟠 Rust core — Correctness fixes

- **DNS cache correctness.** The cache is now keyed by `(domain, qtype)` and
  stamps the current request's transaction id onto cached replies. Previously it
  returned a stale transaction id and ignored the record type, so clients
  rejected cached answers.
- **SafeSearch precision.** Rewrites now match an exact allow-list of search
  hostnames instead of a substring. `mail.google.com` / `drive.google.com` and
  look-alikes such as `google.com.attacker.net` are no longer hijacked.
- **Whitelist covers subdomains + removal wired.** Whitelisting `facebook.com`
  now also allows `graph.facebook.com`. New `aegis_remove_whitelist` /
  `aegis_remove_blacklist` FFI exports are wired through Dart and the provider,
  so removing an entry in the UI actually reaches the engine.
- **DNS-over-HTTPS upstream (RFC 8484).** Cleartext UDP:53 forwarding was
  replaced with a DoH `POST` (`application/dns-message`). The endpoint is an
  IP literal (`https://1.1.1.1/dns-query`) on purpose — resolving a hostname
  here would recurse into our own captured resolver and deadlock.
- **New `packet` module.** Minimal IPv4/UDP parsing, reply reassembly and RFC
  1071 checksum, fully unit-tested.
- **JNI bridge** (`nativeProcessPacket`) for the Android service.
- **Dependency cleanup.** Removed unused `tokio`, `aho-corasick`, `regex`,
  `parking_lot`.
- Rust tests: **6 → 16**, no compiler warnings.

### 🟡 Flutter / Dart

- **Fallback matching fixed.** The pure-Dart fallback matched domains by
  substring (`adnxs.com` blocked `myadnxs.com`). It now matches a domain or its
  subdomains only.
- **Removal wiring + single source of truth.** `removeWhitelist` /
  `removeBlacklist` added; the FFI stub kept in sync with the native bindings;
  seed allow/deny lists are pushed into the engine on startup so the UI and the
  engine agree.
- **Deprecation sweep.** `withOpacity` → `withValues`, `activeColor` →
  `activeThumbColor`. `flutter analyze`: **20 issues → 0**.
- Removed the unused `flutter_rust_bridge` dependency.
- Dart tests: **3 → 5**.

### 🍎 iOS — Partial (needs macOS/Xcode to finish)

- Fixed invalid `fn` keyword (Rust syntax) → `func`; the packet tunnel did not
  compile before.
- The `readPackets` loop now runs each packet through `aegis_process_ip_packet`
  and writes replies back instead of discarding them; the engine C ABI is
  declared in the bridging header.
- **Full integration code prepared** (assembled on a Mac — see
  [`ios/IOS_SETUP.md`](ios/IOS_SETUP.md)): the `PacketTunnelProvider` moved to a
  dedicated `ios/PacketTunnel/` extension folder with DNS-only routing that
  mirrors Android; `VpnManager.swift` wiring the `com.aegisnet/vpn` channel to
  `NETunnelProviderManager`; app + extension entitlements; the extension
  `Info.plist`; and `ios/build_rust_ios.sh` to produce `AegisCore.xcframework`.
- **Rust core verified to cross-compile for iOS** (device + simulator) on a
  macOS CI runner (`.github/workflows/ios.yml`).
- **Still requires macOS + a paid Apple Developer account:** creating the
  Network Extension target, capabilities/provisioning, and linking the
  framework. Runtime testing needs a real iPhone.

### 🧹 Housekeeping

- Confirmed the prebuilt `aegis_core.dll` is git-ignored and untracked.

### 🩹 iOS shell fixes (static review — not yet compiled on a Mac)

- **The VPN channel was never registered.** `AppDelegate` wired
  `com.aegisnet/vpn` from `didFinishLaunchingWithOptions:` via
  `window?.rootViewController`, but this project uses the UIScene lifecycle
  (`SceneDelegate` + `UIApplicationSceneManifest`), where no scene has connected
  at launch and `window` is still nil. Registration moved to
  `didInitializeImplicitFlutterEngine`, which runs before any scene connects.
- **The UI no longer claims protection it does not have.** `AegisBridge.startVpn`
  treated `MissingPluginException` as success, so the missing registration above
  surfaced as a green "protected" dashboard with no tunnel running. Missing
  handlers now count as failure on Android/iOS and remain a no-op only on
  web/desktop, where there is no native side by design. Covered by a regression
  test; Dart tests: **5 → 7**.
- **`ios/Runner.xcworkspace/` was gitignored, which broke every fresh iOS build.**
  The whole directory was excluded in `.gitignore`, so a clean checkout had no
  workspace: `flutter build ios` aborted with *"An error occurred when adding
  Swift Package Manager integration: Exception: Xcode workspace not found"*, and
  anyone cloning on a Mac had to open `Runner.xcodeproj` directly — where the
  generated Swift package cannot be resolved, producing *"Missing package product
  'FlutterGeneratedPluginSwiftPackage'"*. Both reported errors came from this one
  line. The workspace is part of the Flutter template and is now committed.
- **CI stops swallowing iOS build failures.** The `flutter build ios` step is no
  longer `continue-on-error` (the job stays non-blocking), the pointless
  `--no-enable-swift-package-manager` step is gone — `Runner.xcodeproj` is a
  Swift Package Manager project — and the generated
  `ios/Flutter/ephemeral/Packages` state is dumped before the build to diagnose
  "Missing package product 'FlutterGeneratedPluginSwiftPackage'".

## Known follow-ups

- iOS: complete the Network Extension target, entitlements and static-lib
  linkage listed above.
- **iOS: the extension gets its own copy of the engine.** Runner and PacketTunnel
  are separate processes and the Rust engine keeps state in process-local
  globals, so rules pushed from Dart never reach the code doing the filtering.
  Needs a shared-state design over the already-declared App Group — see
  [`ios/IOS_SETUP.md`](ios/IOS_SETUP.md).
- **iOS: link `AegisCore.xcframework` into Runner too**, not just PacketTunnel;
  `DynamicLibrary.process()` finds nothing otherwise and the app silently uses
  placeholder rules and statistics.
- Android: the upstream DoH call is synchronous on the tunnel thread; a
  thread-pool/async path would improve throughput under load.
