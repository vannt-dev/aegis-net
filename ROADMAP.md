# 🗺️ AegisNet Master Implementation Roadmap

> Status legend: **[x]** done & verified · **[~]** partial / needs finishing · **[ ]** not started

## 📍 Phase 1: Native & Cross-Compilation Pipeline
- [x] Rust FFI Export Layer & C-bindings (`api.rs`)
- [x] Android Local TUN Interface — packets filtered through Rust end-to-end
      (`AegisVpnService.kt`), **verified on an Android 34 emulator**
- [x] Android native build via Gradle `cargo-ndk` task (`libaegis_core.so`)
- [~] iOS NetworkExtension (`PacketTunnelProvider.swift`) — packet loop wired to
      the engine, but still needs a Network Extension target, entitlements,
      a `NETunnelProviderManager` start path and `libaegis_core.a` linkage
- [x] Automated CI/CD GitHub Actions Build Workflow

## 📍 Phase 2: Engine Performance & Networking
- [x] Sub-millisecond Rule Engine (Hosts, EasyList, AdGuard format), domain +
      subdomain aware
- [x] DNS over HTTPS (DoH, RFC 8484) with IP-literal upstream (no bootstrap loop)
- [x] `(domain, qtype)` TTL cache with transaction-id rewriting
- [x] Exact-host SafeSearch enforcement (Google, DuckDuckGo)
- [x] Category-Based Filtering (Ads, Trackers, Malware, Adult/Parental)
- [x] App-by-App Split-Tunneling Bypass Support
- [ ] Async / thread-pooled upstream DoH (currently blocking on the tunnel thread)

## 📍 Phase 3: Premium UI/UX & User Customization
- [x] Cyberpunk Glassmorphic Dashboard with Pulsing Power Switch
- [x] Quick Protection Pause (5 min, 15 min, 1 hour)
- [x] Real-time Traffic & Latency Analytics
- [x] Live DNS Query Log with Search & Filter
- [x] Custom Whitelist & Blacklist Manager
- [x] Local Storage Persistence (`shared_preferences`)

## 📍 Phase 4: Security & Store Compliance
- [x] 100% On-Device Zero-Data-Collection Privacy Architecture
- [x] Store-compliant App Description & Privacy Firewall Metadata
