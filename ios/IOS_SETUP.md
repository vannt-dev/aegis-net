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

## Open problem: the extension has its own copy of the engine

On Android the tunnel runs inside the app process, so rules pushed through FFI
and rules used for filtering are the same objects. **On iOS they are not.**
Runner and PacketTunnel are separate processes, and the engine keeps all of its
state in process-local globals (`RULE_ENGINE`, `STATS_ENGINE`, `DNS_FILTER` in
`rust/aegis_core/src/api.rs`).

So every `aegis_add_blacklist` / `aegis_set_category` / `aegis_set_upstream_dns`
the Dart layer makes only mutates the *app's* copy, while `aegis_process_ip_packet`
runs in the *extension's* copy, which has never received a rule. Left as is,
filtering on iOS will use an empty rule set and the app will show statistics that
the tunnel never produced.

The App Group `group.com.aegisnet.app` is already declared in both entitlements
files for exactly this purpose, but nothing reads or writes it yet. Whatever the
design ends up being (shared rules file in the group container that
`startTunnel` loads, stats written back the same way), it has to be decided
before iOS filtering can work.

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
