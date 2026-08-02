# 📓 Changelog

All notable engineering changes to **AegisNet**. This log records the work that
turned the app from a UI shell with mocked data into a working DNS filter with a
verified native pipeline on Android.

## [Unreleased]

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
