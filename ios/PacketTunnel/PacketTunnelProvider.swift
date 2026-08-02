import NetworkExtension

/// Packet Tunnel Provider — the iOS counterpart of Android's `AegisVpnService`.
/// It captures DNS traffic, filters it through the Rust engine
/// (`aegis_process_ip_packet`) and writes synthesized replies back.
///
/// This file belongs to the **PacketTunnel app-extension target**, not the main
/// Runner app. See `ios/IOS_SETUP.md` for how to create that target in Xcode.
class PacketTunnelProvider: NEPacketTunnelProvider {

    /// Virtual DNS server the OS sends queries to. Only this address is routed
    /// into the tunnel, so non-DNS traffic and the engine's own upstream DoH
    /// lookups stay on the real network (mirrors the Android DNS-only routing).
    private let tunnelDnsServer = "10.0.0.3"

    /// Shared with the app; see ios/IOS_SETUP.md. This process has its own copy
    /// of the Rust engine, so the app's rules only arrive through these files.
    private let appGroupId = "group.com.aegisnet.app"
    private let settingsFileName = "settings.json"
    private let statsFileName = "stats.json"

    /// How often the counters this process accumulates are published for the
    /// app to display. Long enough not to matter for battery, short enough that
    /// the dashboard does not look frozen.
    private let statsPublishInterval: TimeInterval = 5

    private var statsTimer: DispatchSourceTimer?

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    enum TunnelError: Error {
        /// The App Group is missing from the provisioning profile, so no rules
        /// can ever be read. Refusing to start beats running a tunnel that
        /// forwards every query unfiltered while the UI claims protection.
        case sharedContainerUnavailable
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let container = containerURL else {
            NSLog("[AegisTunnel] App Group \(appGroupId) unavailable — refusing to start")
            completionHandler(TunnelError.sharedContainerUnavailable)
            return
        }
        loadSharedState(from: container)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: tunnelDnsServer, subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: [tunnelDnsServer])
        dns.matchDomains = [""] // intercept every DNS query
        settings.dnsSettings = dns

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }
            completionHandler(nil)
            self?.startPublishingStats()
            self?.readPackets()
        }
    }

    /// Adopt whatever the app last wrote: user settings first, then each
    /// downloaded filter list. A missing or corrupt file is logged and skipped —
    /// it must not take the tunnel down, unlike a missing container.
    private func loadSharedState(from container: URL) {
        let settingsPath = container.appendingPathComponent(settingsFileName).path
        let status = aegis_import_settings(settingsPath)
        if status != 0 {
            NSLog("[AegisTunnel] no usable settings snapshot (status \(status))")
        }

        // Category ids match the Dart/Rust mapping: 0 Ads, 1 Trackers,
        // 2 Malware, 3 Adult.
        for categoryId in Int32(0)...Int32(3) {
            let path = container.appendingPathComponent("rules_\(categoryId).txt").path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let added = aegis_load_rules_file(path, categoryId)
            NSLog("[AegisTunnel] loaded \(added) rules for category \(categoryId)")
        }
    }

    private func startPublishingStats() {
        guard let container = containerURL else { return }
        let statsPath = container.appendingPathComponent(statsFileName).path

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + statsPublishInterval,
                       repeating: statsPublishInterval)
        timer.setEventHandler {
            _ = aegis_export_stats(statsPath)
        }
        timer.resume()
        statsTimer = timer
    }

    /// The app sends this after changing rules while the tunnel is up. Without
    /// it a rule change would not apply until the VPN was toggled off and on.
    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "reload",
              let container = containerURL else {
            completionHandler?(nil)
            return
        }

        loadSharedState(from: container)
        completionHandler?(Data("ok".utf8))
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            var outPackets: [Data] = []
            var outProtocols: [NSNumber] = []

            for (index, packet) in packets.enumerated() {
                // Hand each IPv4 packet to the Rust engine; a non-empty result
                // is a synthesized DNS reply to write straight back.
                var outBuf = [UInt8](repeating: 0, count: packet.count + 1500)
                let written = packet.withUnsafeBytes { rawIn -> Int in
                    guard let inBase = rawIn.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return outBuf.withUnsafeMutableBufferPointer { outPtr in
                        Int(aegis_process_ip_packet(inBase, packet.count,
                                                    outPtr.baseAddress, outPtr.count))
                    }
                }
                if written > 0 {
                    outPackets.append(Data(outBuf.prefix(written)))
                    outProtocols.append(protocols[index])
                }
            }

            if !outPackets.isEmpty {
                self.packetFlow.writePackets(outPackets, withProtocols: outProtocols)
            }

            self.readPackets()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        statsTimer?.cancel()
        statsTimer = nil

        // Final flush so the app's dashboard reflects the whole session, not
        // whatever the last periodic write happened to catch.
        if let container = containerURL {
            _ = aegis_export_stats(container.appendingPathComponent(statsFileName).path)
        }
        completionHandler()
    }
}
