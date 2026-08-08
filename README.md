# AegisNet 🛡️

**AegisNet** is a high-performance, cross-platform system-wide DNS Privacy Guard & Ad-Blocking Mobile Application for **Android & iOS**, built with **Flutter** and powered by a high-speed **Rust Core Engine**.

---

## 📐 Architecture Overview

```text
               ┌──────────────────────────────────────────────────────────┐
               │                      Flutter UI                          │
               │ (Dashboard, Stats, Rules, Live Logs, Analytics, Settings)│
               └───────────────────────────┬──────────────────────────────┘
                                           │  Dart FFI (dart:ffi)
                                           ▼
 ┌───────────────────────────────────────────────────────────────────────────────────┐
 │                                Rust Core Engine                                   │
 │  ├── Rule Engine (HashSet domain + subdomain matching; Hosts, EasyList, AdGuard)  │
 │  ├── DNS Interceptor & DoH Resolver (Sinkhole 0.0.0.0 for Ads, DNS-over-HTTPS)    │
 │  ├── DNS In-Memory Cache (per (domain, qtype) TTL cache for low latency)          │
 │  ├── SafeSearch Rewriter (exact-host enforcement for Google & DuckDuckGo)         │
 │  ├── Packet Parsing (minimal IPv4/UDP parser + checksum, `packet.rs`)             │
 │  └── Statistics Engine (Real-time counters & ring-buffer query logs)              │
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

- **🚀 Sub-Millisecond DNS Filtering**: Powered by Rust `rule_engine` with a memory-optimized **`DomainTrie` (Prefix Tree)** supporting Hosts format, EasyList DNS, and AdGuard domain rules. Matching is exact-domain **and** subdomain-aware with 50-70% lower memory footprint.
- **⚡ DNS In-Memory Cache**: Rust TTL cache keyed by `(domain, qtype)`, stamping each cached reply with the caller's transaction id for correct resolution.
- **🗺️ Local DNS Mapping & Custom Hosts**: Define custom internal DNS host overrides (`domain` -> `IP`, e.g. `myrouter.local` -> `192.168.1.1`) with real-time UI control.
- **⏰ Scheduled Quiet Hours (Parental Controls)**: Automatic category filter activation during configured quiet hours (e.g. 22:00 - 06:00).
- **🔒 Enforced SafeSearch**: Exact-host SafeSearch rewriting for Google & DuckDuckGo (unrelated subdomains such as `mail.google.com` are never touched).
- **🌐 DNS-over-HTTPS & DoT (RFC 8484)**: Encrypted DoH/DoT upstream (`application/dns-message`) using IP-literal endpoints to avoid resolver bootstrap loops; configurable providers (Cloudflare, Google, AdGuard, Quad9).
- **💻 Multi-Platform Desktop Support**: Desktop scaffolding for Windows, macOS, and Linux powered by `DesktopDnsProxy`.
- **⏱️ DNS Latency Benchmark**: Interactive built-in benchmark tool to test and automatically select the fastest upstream DNS provider.
- **📱 System-Wide Protection**: Intercepts OS-level DNS traffic via local split-tunnel VPN (`VpnService` on Android, `NEPacketTunnelProvider` on iOS) without routing web traffic to remote servers.
- **📊 Real-time Dashboard & Analytics**: Interactive traffic graphs, query counters, ad-block stats, bandwidth savings, and detailed category analytics.
- **📜 Live Query Log & CSV Export**: Real-time query monitoring with status filter chips (`ALL LOGS`, `BLOCKED`, `ALLOWED`), instant domain search and CSV export.
- **⚡ Custom Whitelist & Blacklist**: Flexible custom rule management with instant hot-reloading.
- **🔄 Background Auto-Sync**: Automatic blocklist updates and background rule synchronization.
- **🌍 4-Language i18n Support**: Full internationalization for English (EN), Vietnamese (VI), Korean (KO), and Japanese (JA).
- **🌙 Dynamic Dark/Light Theme**: Seamless theme switching with customizable app settings.

---

## 🎯 What DNS Filtering Can and Cannot Block

AegisNet blocks by **domain name**. It sees which host a device asks for and
answers or refuses; it never looks inside the encrypted connection. That draws a
hard line around what it can do.

**Blocked effectively** — ads and trackers served from their own domains:
banners and interstitials in most free apps and games (AppLovin, Vungle, AdMob
and similar networks), analytics and telemetry endpoints, and web ads while
browsing.

**Not blocked** — ads served from the *same* domains as the content itself:

| App | Why |
|-----|-----|
| **YouTube** | Ads and video both come from `googlevideo.com`. Blocking it blocks the video too. Most YouTube ads are also stitched into the video stream server-side, so there is no separate request to refuse. |
| **Facebook / Instagram** | In-feed ads arrive over the same hosts as the feed. |
| **Spotify, TikTok** | Same pattern: ad content shares the delivery infrastructure. |

This is a property of DNS filtering itself, not a gap in the rule list — no
blocklist can fix it. Removing YouTube ads specifically requires a different
approach, such as an alternative client (ReVanced, NewPipe) or YouTube Premium.

---

## 📊 Platform Status

| Platform | Native DNS filtering | Notes |
|----------|:--------------------:|-------|
| **Android** | ✅ **Working (verified on emulator)** | TUN → Rust → device pipeline, DNS-only routing, DoH upstream. `libaegis_core.so` is built by a Gradle `cargo-ndk` task. |
| **iOS** | 🚧 **App shell builds in CI; filtering not wired up** | The Flutter shell compiles on a macOS runner on every PR. Extension provider, `NETunnelProviderManager` channel, entitlements, App Group state sharing and the Rust framework script are all in the repo, and the Rust core cross-compiles for iOS. Still missing: the `PacketTunnel` target does not exist in the Xcode project, so none of the extension Swift has ever been compiled. Final assembly needs macOS/Xcode + a paid Apple Developer account — see [`ios/IOS_SETUP.md`](ios/IOS_SETUP.md). |
| **Desktop** | ✅ **Scaffolding Ready (Windows/macOS/Linux)** | Full native desktop project scaffolding with `DesktopDnsProxy` integration for local DNS resolution. |
| **Web** | ➖ **Fallback Engine / WASM Ready** | Runs the pure-Dart fallback engine (simulation) with WASM target scaffolding for browser testing. |

> When the native engine is unavailable, the app **gracefully falls back** to a
> pure-Dart simulation engine instead of failing — useful for UI work without a
> native toolchain. See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

---

## 📂 Project Structure

```text
aegis-net/
├── android/                   # Native Android VpnService & MethodChannel
│   └── app/
│       ├── build.gradle.kts   # cargo-ndk preBuild task -> jniLibs
│       └── src/main/
│           ├── jniLibs/       # libaegis_core.so per ABI (built, git-ignored)
│           └── kotlin/com/aegisnet/app/
│               ├── AegisVpnService.kt
│               └── MainActivity.kt
├── ios/                       # Native iOS NEPacketTunnelProvider (WIP)
│   ├── PacketTunnel/           # Extension sources — target NOT created yet, never compiled
│   │   └── PacketTunnelProvider.swift
│   └── Runner/
│       ├── AppDelegate.swift   # registers the channel from didInitializeImplicitFlutterEngine
│       ├── SceneDelegate.swift # UIScene lifecycle (Flutter 3.35+)
│       └── VpnManager.swift    # com.aegisnet/vpn MethodChannel <-> NETunnelProviderManager
├── rust/                      # Rust Core Engine Crate
│   └── aegis_core/
│       ├── Cargo.toml
│       └── src/
│           ├── api.rs         # FFI exported functions & bridge interface
│           ├── cache.rs       # DNS In-Memory (domain, qtype) TTL cache
│           ├── dns_filter.rs  # DNS parser, sinkhole, SafeSearch & DoH upstream
│           ├── rule_engine.rs # Domain + subdomain HashSet matcher
│           ├── packet.rs      # IPv4/UDP parse, reply reassembly & checksum
│           ├── jni_bridge.rs  # JNI entry point for the Android VpnService
│           ├── shared_state.rs # Snapshots crossing the iOS app <-> extension boundary
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
- 📓 **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- 🍎 **iOS Packet Tunnel Setup**: [ios/IOS_SETUP.md](ios/IOS_SETUP.md)

---

## 🛠️ Getting Started (Local Development)

### Prerequisites

1. **Flutter SDK** (v3.0.0+ for Android/Web; **iOS needs 3.35+** — the iOS shell
   uses the UIScene lifecycle APIs `FlutterSceneDelegate` /
   `FlutterImplicitEngineDelegate`, which older SDKs do not have. CI builds on
   stable 3.44.x, matching `.metadata`.)
2. **Rust Toolchain** (`rustup`, `cargo`)
3. **Google Chrome / MS Edge** (for Web local testing) or **Android Studio** / **Visual Studio 2022** (for platform native builds)

---

### 🚀 Quick Start Steps

#### Step 1: Install Flutter Dependencies
```bash
flutter pub get
```

#### Step 2: Build Rust Core Engine (Optional for Web)
> **Note**: If the native engine is not compiled, AegisNet automatically falls back to its built-in **Pure Dart Engine**, allowing UI testing without native compilation.

```bash
cd rust/aegis_core
cargo build --release   # host build (desktop/tests)
cd ../..
```

**Android:** the native library is built automatically. The Gradle `preBuild`
task runs `cargo-ndk` and drops `libaegis_core.so` into `jniLibs` for every ABI,
so a normal `flutter build apk` / `flutter run` produces a filtering-capable
build. It requires the Rust Android targets and `cargo-ndk`:

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk
```

If `cargo-ndk` is not on `PATH`, the task is skipped and the app runs in the
pure-Dart fallback (no crash).

> 💡 **Windows Troubleshooting (`os error 4551`)**:
> If Windows Smart App Control blocks `cargo.exe`, add an exclusion for `~/.cargo` and `~/.rustup` in **Windows Security > App & browser control**, or switch toolchain to GNU (`rustup default stable-x86_64-pc-windows-gnu`).

#### Step 3: Run Locally

* **Run Web Debug Mode (Hot Reload)**:
  ```bash
  flutter run -d chrome
  ```
  *(or `flutter run -d edge`)*

* **Run Web Production Server**:
  ```bash
  flutter build web --release
  npx serve build/web -l 8080
  ```
  Then open [http://localhost:8080](http://localhost:8080) in your browser.

* **Run on iOS** (macOS + Xcode 15+ only):
  ```bash
  flutter build ios --no-codesign      # verify the shell compiles
  flutter run -d <simulator-id>        # flutter devices to list them
  ```
  **There is no CocoaPods in this project** — the only native plugin goes through
  Swift Package Manager, so `pod install` is not a step and will fail with *No
  Podfile found*. If you open Xcode, open **`ios/Runner.xcworkspace`**, not
  `Runner.xcodeproj`; opening the project directly leaves Xcode unable to resolve
  the generated package and it reports *Missing package product
  'FlutterGeneratedPluginSwiftPackage'*.

  DNS filtering does **not** work on iOS yet — the `PacketTunnel` target still
  has to be created in Xcode. See [`ios/IOS_SETUP.md`](ios/IOS_SETUP.md).

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
- **Build & Test** ([`build.yml`](.github/workflows/build.yml)): Rust `cargo check`/`test`, Flutter analyze/test/web build, and Android debug APK build. Runs on every push to `main`/`develop` and every PR.
- **iOS Build Verification** ([`ios.yml`](.github/workflows/ios.yml)): cross-compiles the Rust core for iOS targets and builds the Flutter iOS shell (`flutter build ios --no-codesign`) on a macOS runner. Both jobs gate — a broken iOS shell fails the run. Same triggers as above (push to `main`/`develop`, every PR).
- **Release** ([`release.yml`](.github/workflows/release.yml)): builds, signs and publishes the Android release APK (GitHub Release + Firebase App Distribution). Only runs on `main` — a PR into `main` builds a downloadable artifact without publishing, a push/merge to `main` publishes for real.

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.
