# 🍎 iOS Packet Tunnel — Setup Guide

The iOS DNS filtering runs inside a **Network Extension (Packet Tunnel Provider)**.
All the source is already in the repo, and the **Runner** target is wired
(bundle id, `VpnManager.swift` membership, entitlements) by editing
`project.pbxproj` directly.

None of the Swift in `ios/` has been compiled yet: the CI job
(`.github/workflows/ios.yml`) is marked `continue-on-error` at the job level, so
it reports progress rather than gating, and the `PacketTunnel/` sources belong to
a target that does not exist in the project file yet. Treat every Swift file here
as unverified until it builds on a Mac.

What remains below genuinely needs a **Mac with Xcode**: creating the extension
target, linking the Rust `xcframework`, provisioning, and device testing.

## Prerequisites (hard requirements)

- **macOS + Xcode 15+** — Network Extension targets can only be created/built here.
- **Paid Apple Developer account ($99/yr)** — the
  `com.apple.developer.networking.networkextension` entitlement is a *special*
  entitlement; free accounts **cannot** build a packet tunnel.
- **A real iPhone** for runtime testing — the Simulator does not run packet
  tunnels.

## Files already prepared in this repo

| File | Role |
|------|------|
| `ios/Runner/VpnManager.swift` | MethodChannel `com.aegisnet/vpn` → `NETunnelProviderManager` (install/start/stop) |
| `ios/Runner/AppDelegate.swift` | Registers the channel from `didInitializeImplicitFlutterEngine` (not `didFinishLaunching:` — under UIScene there is no window yet) |
| `ios/Runner/Runner.entitlements` | App: NetworkExtension + App Group |
| `ios/PacketTunnel/PacketTunnelProvider.swift` | The tunnel: DNS-only routing → Rust engine → write replies |
| `ios/PacketTunnel/PacketTunnel-Bridging-Header.h` | C ABI decl for `aegis_process_ip_packet` |
| `ios/PacketTunnel/Info.plist` | Declares the `NEPacketTunnelProvider` principal class |
| `ios/PacketTunnel/PacketTunnel.entitlements` | Extension: NetworkExtension + App Group |
| `ios/build_rust_ios.sh` | Builds `AegisCore.xcframework` from the Rust crate |

## Steps (on the Mac)

### 1. Build the Rust engine framework
```bash
./ios/build_rust_ios.sh          # → ios/Frameworks/AegisCore.xcframework
```

### 2. Select your signing team

Already wired in `Runner.xcodeproj/project.pbxproj` — **nothing to do here**
beyond picking a team:

- Bundle Identifier is `com.aegisnet.app` (and `com.aegisnet.app.RunnerTests`),
  matching the Android `applicationId`.
- `VpnManager.swift` is a member of the Runner target, so the
  `AppDelegate.swift` reference to it resolves.
- `CODE_SIGN_ENTITLEMENTS` points at `Runner/Runner.entitlements` for all three
  build configurations.

In Xcode → **Runner** target → *Signing & Capabilities*, select your paid
**Team**. That still cannot be scripted — it is tied to your developer account.

### 3. Add the Packet Tunnel extension target
- **File → New → Target… → Network Extension** (Packet Tunnel Provider).
- Name it **PacketTunnel**, bundle id `com.aegisnet.app.PacketTunnel`.
- Delete the auto-generated `PacketTunnelProvider.swift`; instead **add the
  existing files** from `ios/PacketTunnel/` (Provider, Info.plist, bridging
  header) to this target.
- In the target's *Build Settings*, set **Objective-C Bridging Header** to
  `PacketTunnel/PacketTunnel-Bridging-Header.h`.

### 4. Capabilities & entitlements
On **both** the Runner target and the PacketTunnel target, add:
- **Network Extensions** → *Packet Tunnel Provider*.
- **App Groups** → `group.com.aegisnet.app`.

Point each target at the matching `*.entitlements` file (already in the repo).

### 5. Link the Rust framework — into **both** targets
Drag `ios/Frameworks/AegisCore.xcframework` into the project and add it to the
*Frameworks and Libraries* of:

- the **PacketTunnel** target — resolves `aegis_process_ip_packet`;
- the **Runner** target — resolves the FFI symbols the Dart side looks up.

Use *Do Not Embed* for a static library. Runner is easy to forget: on iOS
`lib/src/bridge/ffi_native.dart` loads the engine with
`DynamicLibrary.process()`, which only finds symbols already linked into the
running binary (there is no `.so` to `dlopen`). If the library is linked into the
extension only, every lookup throws, `AegisBridge._useNativeFfi` stays false and
the app silently falls back to the hard-coded placeholder rules and statistics
instead of the real engine.

### 6. Provisioning
Create App IDs for `com.aegisnet.app` and `com.aegisnet.app.PacketTunnel` in the
Developer portal, enable **Network Extensions** + **App Groups** on both, and
let Xcode generate/download provisioning profiles.

### 7. Build & run on a device
```bash
flutter run --release        # on a connected iPhone
```
Tap **START** → accept the "Allow VPN configuration" prompt. Verify filtering,
e.g. a blocked domain resolves to a null address while normal domains resolve.

## Sharing state between the app and the extension

On Android the tunnel runs inside the app process, so rules pushed through FFI
and rules used for filtering are the same objects. **On iOS they are not.**
Runner and PacketTunnel are separate processes, and the engine keeps all of its
state in process-local globals (`RULE_ENGINE`, `STATS_ENGINE`, `DNS_FILTER` in
`rust/aegis_core/src/api.rs`).

So every `aegis_add_blacklist` / `aegis_set_category` / `aegis_set_upstream_dns`
the Dart layer makes only mutates the *app's* copy, while `aegis_process_ip_packet`
runs in the *extension's* copy. Without the mechanism below, filtering on iOS
uses an empty rule set while the app shows statistics the tunnel never produced.

### Design

The app stays the owner of the configuration and keeps its own engine for the UI
(matching Android); the extension is a consumer that reloads on demand.
Statistics flow the other way. Everything crosses through the App Group
container `group.com.aegisnet.app`, already declared in both entitlements files.

**The snapshot format is owned by Rust, not by Swift**, so both processes go
through one code path and it can be round-trip tested with `cargo test` on any
platform — the only part of this that is verifiable without a Mac.

Two kinds of data, split because their sizes differ by orders of magnitude:

| Data | Size | Mechanism |
|------|------|-----------|
| Settings — enabled categories, whitelist, blacklist, upstream DoH | a few KB | JSON snapshot via `aegis_export_settings` / `aegis_import_settings` |
| Downloaded filter lists | 128k+ lines, MBs | raw `.txt` written into the container by the downloader, read back with `aegis_load_rules_file` |
| Statistics | small | JSON snapshot via `aegis_export_stats` / `aegis_import_stats` |

### C ABI added for this

```c
int32_t aegis_export_settings(const char *path);   // app  → container
int32_t aegis_import_settings(const char *path);   // container → extension
uint32_t aegis_load_rules_file(const char *path, int32_t category_id);
int32_t aegis_export_stats(const char *path);      // extension → container
int32_t aegis_import_stats(const char *path);      // container → app
```

All return `0` on success / a negative error code, and never panic across the
FFI boundary: a missing or corrupt snapshot is an error code, not a crash.

### Data flow

1. Dart changes a rule → `AegisBridge` calls `aegis_export_settings` into the
   container. The path comes from a new `getSharedContainerPath` method on the
   existing `com.aegisnet/vpn` channel, since only Swift can resolve an App Group
   URL.
2. `startTunnel` resolves the container, calls `aegis_import_settings` plus
   `aegis_load_rules_file` for each cached list, and only then starts
   `readPackets()`.
3. Rules edited while the tunnel is up → the app sends `sendProviderMessage`
   with a `reload` payload; `handleAppMessage` re-imports. Without this step a
   rule change would not take effect until the VPN is toggled off and on.
4. The extension periodically calls `aegis_export_stats`; the app calls
   `aegis_import_stats` before reading `aegis_get_stats_json`, so the dashboard
   shows numbers the tunnel actually produced instead of its own local counters.

### Error handling

If the App Group container cannot be resolved — the usual cause is provisioning
that does not carry the App Group capability — `startTunnel` **fails** instead of
continuing. A tunnel with no rules loaded forwards every DNS query unfiltered
while the UI reports "protected", which is precisely the class of bug the
`MissingPluginException` fix removed. Failing loudly is the honest behaviour.

A missing or corrupt snapshot file is different: it is logged and treated as an
empty configuration, because it must not take the tunnel down.

### What is testable where

- Rust round-trips (export → import → identical blocking decisions, plus corrupt
  and missing input) run in `cargo test`, so CI covers them on every push.
- Runner-side Swift is compiled by the macOS CI job.
- Extension-side Swift stays unverified until the PacketTunnel target exists.

## Notes

- The provider routes only the virtual DNS server (`10.0.0.3`) through the
  tunnel, mirroring Android, so non-DNS traffic and the engine's upstream DoH
  lookups stay on the real network (no loop, no `protect()` needed).
- Signing: the project sets `CODE_SIGN_ENTITLEMENTS` for all three
  configurations but has no `DEVELOPMENT_TEAM`. `flutter build ios --no-codesign`
  works (signing is skipped), but `flutter build ipa` / archiving will fail until
  a team is selected **and** the PacketTunnel target exists — an app that claims
  `com.apple.developer.networking.networkextension` without shipping the
  extension cannot get a matching provisioning profile.
- Runtime VPN behavior can only be checked on a real device; the Simulator does
  not run packet tunnels.
