import Flutter
import NetworkExtension

/// Bridges the Flutter `com.aegisnet/vpn` MethodChannel to iOS's
/// `NETunnelProviderManager`, the iOS equivalent of Android's MainActivity VPN
/// handler. Installs and starts/stops the PacketTunnel extension.
final class VpnManager {
    static let shared = VpnManager()

    private let channelName = "com.aegisnet/vpn"

    /// App Group shared with the PacketTunnel extension. The two processes have
    /// separate copies of the Rust engine and exchange state through files here.
    static let appGroupId = "group.com.aegisnet.app"

    /// Bundle id of the PacketTunnel app-extension (main app id + ".PacketTunnel").
    private var providerBundleId: String {
        (Bundle.main.bundleIdentifier ?? "com.aegisnet.app") + ".PacketTunnel"
    }

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "startVpn": self?.startVpn(result)
            case "stopVpn": self?.stopVpn(result)
            case "isVpnPrepared": self?.isPrepared(result)
            case "getSharedContainerPath": self?.sharedContainerPath(result)
            case "reloadTunnelConfig": self?.reloadTunnelConfig(result)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Path Dart writes snapshots to. Nil when the App Group is missing from the
    /// provisioning profile — Dart then skips the snapshot work entirely rather
    /// than writing somewhere the extension cannot read.
    private func sharedContainerPath(_ result: @escaping FlutterResult) {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: VpnManager.appGroupId
        ) else {
            NSLog("[AegisVPN] App Group \(VpnManager.appGroupId) unavailable")
            result(nil)
            return
        }
        result(url.path)
    }

    /// Tell a running tunnel to re-read the settings snapshot. Nothing to do
    /// when no tunnel is up: it loads the snapshot on start anyway.
    private func reloadTunnelConfig(_ result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            guard
                let session = managers?.first?.connection as? NETunnelProviderSession,
                session.status == .connected
            else {
                result(false)
                return
            }

            do {
                try session.sendProviderMessage(Data("reload".utf8)) { _ in }
                result(true)
            } catch {
                NSLog("[AegisVPN] reload message failed: \(error)")
                result(false)
            }
        }
    }

    private func loadOrCreateManager(_ completion: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                NSLog("[AegisVPN] load error: \(error)")
                completion(nil)
                return
            }
            completion(managers?.first ?? NETunnelProviderManager())
        }
    }

    private func startVpn(_ result: @escaping FlutterResult) {
        loadOrCreateManager { [weak self] manager in
            guard let self = self, let manager = manager else { result(false); return }

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.providerBundleId
            proto.serverAddress = "AegisNet"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "AegisNet Shield"
            manager.isEnabled = true

            // First save shows the system "Allow VPN configuration" prompt.
            manager.saveToPreferences { error in
                if let error = error {
                    NSLog("[AegisVPN] save error: \(error)")
                    result(false)
                    return
                }
                manager.loadFromPreferences { error in
                    if let error = error {
                        NSLog("[AegisVPN] reload error: \(error)")
                        result(false)
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel()
                        result(true)
                    } catch {
                        NSLog("[AegisVPN] start error: \(error)")
                        result(false)
                    }
                }
            }
        }
    }

    private func stopVpn(_ result: @escaping FlutterResult) {
        loadOrCreateManager { manager in
            manager?.connection.stopVPNTunnel()
            result(true)
        }
    }

    private func isPrepared(_ result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            result((managers?.isEmpty == false))
        }
    }
}
