# AegisNet 🛡️

**AegisNet** is a high-performance, cross-platform system-wide DNS Privacy Guard & Ad-Blocking Mobile Application for **Android & iOS**, built with **Flutter** and powered by a high-speed **Rust Core Engine**.

---

## 📐 Architecture Overview

```text
               ┌────────────────────────────────────────────────────────┐
               │                      Flutter UI                        │
               │ (Dashboard, Stats, Rules, Live Logs, Analytics, Settings)│
               └───────────────────────────┬────────────────────────────┘
                                           │  Dart FFI / flutter_rust_bridge
                                           ▼
 ┌───────────────────────────────────────────────────────────────────────────────────┐
 │                                Rust Core Engine                                   │
 │  ├── Rule Engine (Trie / Aho-Corasick domain matching, Hosts, EasyList, AdGuard) │
 │  ├── DNS Interceptor & DoH Resolver (Sinkhole 0.0.0.0 for Ads, DNS-over-HTTPS)    │
 │  ├── DNS In-Memory Cache (TTL & LRU caching for ultra-low latency)                │
 │  ├── SafeSearch Rewriter (Google, Bing, DuckDuckGo, YouTube enforced search)       │
 │  ├── Packet Parsing (smoltcp / lwIP)                                              │
 │  └── Statistics Engine (Real-time counters & ring-buffer query logs)             │
 └─────────────────────────────────────────▲─────────────────────────────────────────┘
                                           │  File Descriptor / IP Packets
                                           ▼
 ┌───────────────────────────────────────────────────────────────────────────────────┐
 │                            Native OS Layer (Local VPN)                            │
 │  Android: VpnService (TUN interface & MethodChannel)                              │
 │  iOS:     NEPacketTunnelProvider (NetworkExtension framework)                     │
 └───────────────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Key Features

- **🚀 Sub-Millisecond DNS Filtering**: Powered by Rust `rule_engine` with support for Hosts format, EasyList DNS, and AdGuard domain rules.
- **⚡ Ultra-Fast DNS In-Memory Cache**: Built-in TTL & LRU caching layer in Rust for instantaneous DNS query resolution.
- **🔒 Enforced SafeSearch**: Automatic SafeSearch DNS rewriting for Google, Bing, DuckDuckGo, YouTube, and Yahoo.
- **🌐 DNS-over-HTTPS (DoH)**: Built-in encrypted DoH resolver with configurable fallback upstream DNS options (Cloudflare, Google, AdGuard, Quad9).
- **⏱️ DNS Latency Benchmark**: Interactive built-in benchmark tool to test and automatically select the fastest upstream DNS provider.
- **📱 System-Wide Protection**: Intercepts OS-level DNS traffic via local split-tunnel VPN (`VpnService` on Android, `NEPacketTunnelProvider` on iOS) without routing web traffic to remote servers.
- **📊 Real-time Dashboard & Analytics**: Interactive traffic graphs, query counters, ad-block stats, bandwidth savings, and detailed category analytics.
- **📜 Live Query Log & CSV Export**: Real-time query monitoring with instant domain search and CSV export functionality.
- **⚡ Custom Whitelist & Blacklist**: Flexible custom rule management with instant hot-reloading.
- **🔄 Background Auto-Sync**: Automatic blocklist updates and background rule synchronization.
- **🌍 4-Language i18n Support**: Full internationalization for English (EN), Vietnamese (VI), Korean (KO), and Japanese (JA).
- **🌙 Dynamic Dark/Light Theme**: Seamless theme switching with customizable app settings.

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
│           ├── api.rs         # FFI exported functions & bridge interface
│           ├── cache.rs       # DNS In-Memory TTL/LRU Cache
│           ├── dns_filter.rs  # DNS packet parser, sinkhole & SafeSearch rewrite
│           ├── rule_engine.rs # High-speed Trie/Aho-Corasick domain matcher
│           ├── statistics.rs  # Ring buffer logs & real-time counter statistics
│           └── lib.rs
├── lib/                       # Flutter Application (Dart)
│   ├── main.dart
│   └── src/
│       ├── bridge/            # Flutter-Rust FFI & Native VPN Channel
│       ├── i18n/              # 4-language string localization (EN, VI, KO, JA)
│       ├── providers/         # State management (VpnProvider, ThemeProvider)
│       ├── screens/           # Dashboard, Analytics, Rules, Logs, Settings
│       └── services/          # DNS Benchmark & Rule Downloader Services
├── .githooks/                 # Pre-commit & Pre-push Git hooks
├── .github/workflows/         # CI/CD workflows (Build & Test matrix)
├── pubspec.yaml
└── README.md
```

---

## 📚 Documentation & Guides

For detailed setup, building, testing, and deployment instructions, refer to the project documentation:

- 📖 **User Guide**: [USER_GUIDE.md](USER_GUIDE.md) | [USER_GUIDE_EN.md](USER_GUIDE_EN.md)
- 🛠️ **Build Guide**: [BUILD_GUIDE.md](BUILD_GUIDE.md) | [BUILD_GUIDE_EN.md](BUILD_GUIDE_EN.md)
- 🚀 **Google Play Store Deployment**: [GOOGLE_PLAY_DEPLOYMENT_GUIDE.md](GOOGLE_PLAY_DEPLOYMENT_GUIDE.md)
- 🍎 **Apple App Store Deployment**: [APP_STORE_DEPLOYMENT_GUIDE.md](APP_STORE_DEPLOYMENT_GUIDE.md)
- 🗺️ **Product Roadmap**: [ROADMAP.md](ROADMAP.md)

---

## 🛠️ Getting Started

### Prerequisites

1. **Flutter SDK** (v3.0.0+)
2. **Rust Toolchain** (`rustup`, `cargo`)
3. **Android Studio / Xcode** (for platform builds)

### 1. Build Rust Core Engine

```bash
cd rust/aegis_core
cargo build --release
cd ../..
```

### 2. Run Flutter App

```bash
flutter pub get
flutter run
```

---

## 🧪 Testing & Code Quality

### Run Tests

- **Flutter Unit Tests**:
  ```bash
  flutter test
  ```
- **Rust Core Tests**:
  ```bash
  cd rust/aegis_core
  cargo test
  ```

### Code Formatting & Quality Checks

```bash
# Flutter Analysis & Format
flutter analyze
dart format --output=none --set-exit-if-changed .

# Rust Format & Lints
cd rust/aegis_core
cargo fmt --check
cargo clippy -- -D warnings
```

---

## 🔄 CI/CD & Automation

AegisNet uses GitHub Actions for CI/CD with parallel job execution, Cargo & Gradle caching, and automated verification:

- **Git Hooks**: Pre-commit formatting & strict pre-push test gate (`.githooks/`).
- **CI Pipeline**: Automated build, linting, and unit test matrix on every push/PR (`.github/workflows/ci.yml`).

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.
