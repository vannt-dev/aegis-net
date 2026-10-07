# 🗺️ AegisNet Master Implementation Roadmap

> Status legend: **[x]** done & verified · **[~]** partial / needs finishing · **[ ]** not started

## 📍 Phase 1: Native & Cross-Compilation Pipeline
- [x] Rust FFI Export Layer & C-bindings (`api.rs`)
- [x] Android Local TUN Interface — packets filtered through Rust end-to-end
      (`AegisVpnService.kt`), **verified on an Android 34 emulator**
- [x] Android native build via Gradle `cargo-ndk` task (`libaegis_core.so`)
- [~] iOS NetworkExtension (`PacketTunnelProvider.swift`) — packet loop wired to
      the engine; entitlements, the `NETunnelProviderManager` start path
      (`VpnManager.swift`) and app↔extension state sharing over the App Group
      (`shared_state.rs`) are all in place, and the Flutter shell builds in CI.
      The extension target is now created by `ios/add_packet_tunnel_target.rb`
      (which also links `AegisCore.xcframework` into both targets), but none of
      the extension Swift has been compiled or run on a device yet — that needs
      a Mac. Signing team and App IDs stay manual
- [x] Automated CI/CD GitHub Actions Build Workflow

## 📍 Phase 2: Engine Performance & Networking
- [x] Sub-millisecond Rule Engine (Hosts, EasyList, AdGuard format), domain +
      subdomain aware
- [x] DNS over HTTPS (DoH, RFC 8484) with IP-literal upstream (no bootstrap loop)
- [x] `(domain, qtype)` TTL cache with transaction-id rewriting
- [x] Exact-host SafeSearch enforcement (Google, DuckDuckGo)
- [x] Category-Based Filtering (Ads, Trackers, Malware, Adult/Parental)
- [x] App-by-App Split-Tunneling Bypass Support
- [x] Thread-pooled upstream DoH on both platforms — Android `AegisVpnService`
      (**verified on an Android 14 emulator**) and iOS `PacketTunnelProvider`
      both filter on an 8-worker pool, so a cache miss no longer stalls every
      other query. The iOS half has not been run on a device yet, because the
      extension target was only just added
- [x] DomainTrie prefix tree for domain + subdomain matching (label-per-node,
      so a whole zone costs one terminal instead of one entry per host).
      Measured at 300k rules: 15.7–31.9 MB depending on rule shape, against
      17.5–18.4 MB for the `HashSet` it replaced, and ~170 ns per lookup. The
      trie's win is zone coverage, not raw speed
- [x] Local DNS Mapper & Custom Hosts Override (domain -> IP mapping), carried
      across the iOS app↔extension boundary in the settings snapshot
- [x] IPv6 DNS interception (`fd00:aeed::3`), closing the v6 resolver leak on
      MIUI / Android 14
- [x] Scheduled Parental Control / Quiet Hours Blocking, restoring the user's
      own category setting when the window ends
- [x] Intercept hardcoded public resolvers (Google, Cloudflare, Quad9,
      OpenDNS, AdGuard, CleanBrowsing): their addresses are routed into the
      tunnel, plain DNS to them is filtered, DoT/DoH/DoQ is refused (TCP reset,
      ICMP port-unreachable) so apps fall back, and public DoH host names are
      blocked. The earlier attempt broke DNS because the routes captured the
      engine's own upstream; the app now excludes itself from the VPN.
- [x] Block an app: refuse every lookup made by a chosen Android UID
      (Android 10+). The list is held in the engine and checked before any
      other rule; the app keeps it by package name
- [x] Real DNS-over-TLS transport (RFC 7858, port 853) in the Rust core
      (`dot.rs`): `tls://host[:port][#name]` and `dot://` upstreams, certificate
      verified against the host or the name after `#`, connections reused.
      Checked against Cloudflare, Google and Quad9 from a desktop build and
      cross-compiled for Android arm64; **not yet run on a device or emulator**.
      No EDNS padding yet

## 📍 Phase 3: Premium UI/UX & User Customization
- [x] Cyberpunk Glassmorphic Dashboard with Pulsing Power Switch
- [x] Quick Protection Pause (5 min, 15 min, 1 hour)
- [x] Real-time Traffic & Latency Analytics
- [x] Live DNS Query Log with Search, Status Filter & CSV Export
- [x] Custom Whitelist, Blacklist & Local DNS Hosts Manager
- [x] Local Storage Persistence (`shared_preferences`) & Full JSON Backup/Restore

## 📍 Phase 4: Security & Store Compliance
- [x] 100% On-Device Zero-Data-Collection Privacy Architecture
- [x] Store-compliant App Description & Privacy Firewall Metadata

## 📍 Phase 5: Desktop
- [x] Local DNS resolver (`DesktopDnsProxy`) — answers through the same engine
      as the mobile tunnels, binds 53 (falls back to 5300), never drops a query.
- [x] Desktop platform scaffolding (`windows/`, `macos/`, `linux/`) added to the repository.
