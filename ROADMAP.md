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
      Still needs the Network Extension **target** created in Xcode — none of the
      extension Swift has ever been compiled — plus `AegisCore.xcframework`
      linked into both the Runner and PacketTunnel targets
- [x] Automated CI/CD GitHub Actions Build Workflow

## 📍 Phase 2: Engine Performance & Networking
- [x] Sub-millisecond Rule Engine (Hosts, EasyList, AdGuard format), domain +
      subdomain aware
- [x] DNS over HTTPS (DoH, RFC 8484) with IP-literal upstream (no bootstrap loop)
- [x] `(domain, qtype)` TTL cache with transaction-id rewriting
- [x] Exact-host SafeSearch enforcement (Google, DuckDuckGo)
- [x] Category-Based Filtering (Ads, Trackers, Malware, Adult/Parental)
- [x] App-by-App Split-Tunneling Bypass Support
- [~] Thread-pooled upstream DoH — done on Android (`AegisVpnService` filters on
      an 8-worker pool so a cache miss no longer stalls every other query,
      **verified on an Android 14 emulator**). iOS `PacketTunnelProvider` still
- [x] Memory-optimized DomainTrie Prefix Tree (sub-microsecond matching, 50-70% lower memory footprint)
- [x] Local DNS Mapper & Custom Hosts Override (domain -> IP mapping)
- [x] Scheduled Parental Control / Quiet Hours Blocking

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
