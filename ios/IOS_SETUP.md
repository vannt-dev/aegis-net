# 🍎 iOS Packet Tunnel — Setup Guide

The iOS DNS filtering runs inside a **Network Extension (Packet Tunnel Provider)**.
All the source is already in the repo, and the **Runner** target is fully wired
(bundle id, `VpnManager.swift` membership, entitlements) — that part was done by
editing `project.pbxproj` directly, and is verified by the macOS CI job.

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
| `ios/Runner/AppDelegate.swift` | Registers the channel on launch |
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

### 5. Link the Rust framework
Drag `ios/Frameworks/AegisCore.xcframework` into the project and add it to the
**PacketTunnel** target's *Frameworks and Libraries* (Do Not Embed for a static
library). This resolves `aegis_process_ip_packet`.

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

## Notes

- The provider routes only the virtual DNS server (`10.0.0.3`) through the
  tunnel, mirroring Android, so non-DNS traffic and the engine's upstream DoH
  lookups stay on the real network (no loop, no `protect()` needed).
- Automated **compile** verification runs in CI on a macOS runner
  (`.github/workflows/ios.yml`), but runtime VPN behavior can only be checked on
  a real device.
