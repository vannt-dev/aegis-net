# 🍎 iOS Packet Tunnel — Setup Guide

The iOS DNS filtering runs inside a **Network Extension (Packet Tunnel Provider)**.
All the source is already in the repo; the steps below are the parts that
**must** be done on a **Mac with Xcode** and can't be scripted from Windows.

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

### 2. Set the app bundle id & add the new Runner files
In Xcode → **Runner** target → *Signing & Capabilities*:
- Set **Bundle Identifier** to `com.aegisnet.app` (currently `com.example.aegisNet`).
- Select your paid **Team**.

> The repo adds `ios/Runner/VpnManager.swift` and `ios/Runner/Runner.entitlements`,
> which are **not yet in the Xcode project**. Add `VpnManager.swift` to the
> Runner target (drag it in, ensure *Target Membership → Runner* is checked) —
> `AppDelegate.swift` references it. Point the target's *Code Signing
> Entitlements* build setting at `Runner/Runner.entitlements`.

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
