# AegisNet 🛡️

**AegisNet** is a high-performance, cross-platform system-wide DNS Privacy Guard & Ad-Blocking Mobile Application for **Android & iOS**, built with **Flutter** and powered by a **Rust Core Engine**.

---

## 📐 Architecture Overview

```text
               ┌────────────────────────────────────────┐
               │              Flutter UI                │
               │ (Dashboard, Stats, Rule Manager, Logs) │
               └───────────────────┬────────────────────┘
                                   │  Dart FFI / flutter_rust_bridge
                                   ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │                           Rust Core Engine                             │
 │  ├── Rule Engine (Trie / Aho-Corasick domain matching)                 │
 │  ├── DNS Interceptor & Resolver (Sinkhole 0.0.0.0 for Ads)             │
 │  ├── Packet Parsing (smoltcp / lwIP)                                   │
 │  └── Statistics Engine (Real-time counters & query logs)               │
 └─────────────────────────────────▲──────────────────────────────────────┘
                                   │  File Descriptor / IP Packets
                                   ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │                     Native OS Layer (Local VPN)                        │
 │  Android: VpnService (TUN interface)                                   │
 │  iOS:     NEPacketTunnelProvider (NetworkExtension)                    │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Key Features

- **🚀 Sub-millisecond DNS Filtering**: Powered by Rust `rule_engine` with support for Hosts format, EasyList DNS, and AdGuard lists.
- **📱 System-Wide Protection**: Captures OS DNS traffic via local split-tunnel VPN (`VpnService` on Android, `NEPacketTunnelProvider` on iOS) without routing actual web traffic through external servers.
- **📊 Real-time Dashboard**: Interactive traffic chart, query count, blocked ads counter, and estimated bandwidth savings.
- **📜 Live Query Log**: Monitor allowed vs blocked domain queries with instant search filtering.
- **⚡ Custom Whitelist & Blacklist**: Add custom domain rules instantly.
- **⚙️ Configurable Upstream DNS**: Choose between Cloudflare (1.1.1.1), Google (8.8.8.8), AdGuard, or Quad9.

---

## 📂 Project Structure

```text
aegis-net/
├── android/                   # Native Android VpnService & MethodChannel
│   └── app/src/main/kotlin/com/aegisnet/app/
│       ├── AegisVpnService.kt
│       └── MainActivity.kt
├── ios/                       # Native iOS NEPacketTunnelProvider
│   └── Runner/
│       └── PacketTunnelProvider.swift
├── rust/                      # Rust Core Engine Crate
│   └── aegis_core/
│       ├── Cargo.toml
│       └── src/
│           ├── api.rs         # FFI exported functions
│           ├── dns_filter.rs  # DNS parser & sinkhole
│           ├── rule_engine.rs # Domain matcher
│           ├── statistics.rs  # Ring buffer logs & counters
│           └── lib.rs
├── lib/                       # Flutter Application (Dart)
│   ├── main.dart
│   └── src/
│       ├── bridge/            # Flutter-Rust FFI & VPN Channel
│       ├── providers/         # VpnProvider state management
│       └── screens/           # Dashboard, Rules, Logs, Settings
└── pubspec.yaml
```

---

## 🛠️ Getting Started

### Prerequisites

1. **Flutter SDK** (v3.0.0+)
2. **Rust Toolchain** (`rustup`, `cargo`)
3. **Android Studio / Xcode**

### Build Rust Core

```bash
cd rust/aegis_core
cargo build --release
```

### Run Flutter App

```bash
flutter pub get
flutter run
```

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.
