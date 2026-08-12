import NetworkExtension

/// Packet Tunnel Provider — the iOS counterpart of Android's `AegisVpnService`.
/// It captures DNS traffic, filters it through the Rust engine
/// (`aegis_process_ip_packet`) and writes synthesized replies back.
///
/// This file belongs to the **PacketTunnel app-extension target**, not the main
/// Runner app. See `ios/IOS_SETUP.md` for how to create that target in Xcode.
class PacketTunnelProvider: NEPacketTunnelProvider {

    /// Virtual DNS servers the OS sends queries to. Only these addresses are
    /// routed into the tunnel, so non-DNS traffic and the engine's own upstream
    /// DoH lookups stay on the real network (mirrors the Android DNS-only
    /// routing).
    ///
    /// The v6 half matters on IPv6-only carrier networks, where advertising a
    /// v4-only resolver leaves the system with nothing usable to ask.
    private let tunnelDnsServer = "10.0.0.3"
    private let tunnelDnsServerV6 = "fd00:aeed::3"
    private let tunnelAddressV6 = "fd00:aeed::2"

    /// Concurrent upstream lookups before queries start being dropped,
    /// mirroring `AegisVpnService.WORKER_THREADS` on Android.
    private static let workerCount = 8

    /// Filtering runs here, off the packetFlow callback. `aegis_process_ip_packet`
    /// blocks for a whole upstream DoH round trip on a cache miss, so doing it
    /// inline made every DNS query on the device wait behind one lookup.
    private let filterQueue = DispatchQueue(
        label: "com.aegisnet.tunnel.filter",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Serialises writes back into the tunnel. Workers finish out of order and
    /// two of them writing at once can interleave into a torn packet.
    private let writeQueue = DispatchQueue(label: "com.aegisnet.tunnel.write")

    /// Caps in-flight work so a stalled upstream cannot pile up unbounded
    /// packets in an extension with a hard memory limit.
    private let workerSlots = DispatchSemaphore(value: PacketTunnelProvider.workerCount)

    /// Queries dropped because every worker was busy. Invisible otherwise, and
    /// the difference between "the upstream is slow" and "we are dropping
    /// traffic" is the first thing worth knowing when filtering misbehaves.
    private var droppedUnderLoad: UInt64 = 0

    /// Cleared by `stopTunnel` so the read loop stops re-arming itself.
    private var isRunning = true
    private let stateLock = NSLock()

    private var running: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return isRunning }
        set { stateLock.lock(); isRunning = newValue; stateLock.unlock() }
    }

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
        _ = aegis_init()
        running = true
        loadSharedState(from: container)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: tunnelDnsServer, subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4

        // Without a v6 resolver the system has nothing to ask on IPv6-only
        // carrier networks, and on dual-stack it can prefer a v6 resolver
        // learned outside the tunnel — a DNS leak straight past the filter.
        let ipv6 = NEIPv6Settings(addresses: [tunnelAddressV6], networkPrefixLengths: [128])
        ipv6.includedRoutes = [
            NEIPv6Route(destinationAddress: tunnelDnsServerV6, networkPrefixLength: 128)
        ]
        settings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: [tunnelDnsServer, tunnelDnsServerV6])
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
            // -3 is a version mismatch, which in practice means the app and
            // this extension were built from different copies of the Rust
            // engine. Filtering then runs on defaults only, so say so loudly.
            NSLog("[AegisTunnel] no usable settings snapshot (status \(status))")
        }

        // Loading only inserts, and this runs again on every reload message,
        // so start from a clean slate or an unsubscribed list keeps blocking
        // for as long as the extension process lives.
        aegis_clear_downloaded_rules()

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

    /// Reads the tunnel and hands each packet to the filter pool.
    ///
    /// The read re-arms immediately; filtering does not happen here.
    /// `aegis_process_ip_packet` blocks for the whole upstream DoH round trip
    /// on a cache miss, so running it on this callback made every DNS query on
    /// the device queue behind that one lookup. This mirrors the worker pool
    /// `AegisVpnService` uses on Android.
    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.running else { return }

            for (index, packet) in packets.enumerated() {
                let proto = protocols[index]

                // Bound the in-flight work: an extension has a hard memory
                // limit, and a stalled upstream would otherwise let packets
                // pile up until the process is killed.
                //
                // Dropping beats blocking here — this is a system callback,
                // and stalling it would freeze the read loop for every query
                // rather than just this one. A resolver under load drops too,
                // and the client retries; just count it, or it is invisible.
                guard self.workerSlots.wait(timeout: .now()) == .success else {
                    self.droppedUnderLoad += 1
                    if self.droppedUnderLoad % 100 == 1 {
                        NSLog("[AegisTunnel] dropped \(self.droppedUnderLoad) queries under load")
                    }
                    continue
                }

                self.filterQueue.async {
                    defer { self.workerSlots.signal() }
                    guard self.running else { return }

                    if let reply = self.filter(packet) {
                        // Serialised: workers finish out of order.
                        self.writeQueue.async {
                            guard self.running else { return }
                            self.packetFlow.writePackets([reply], withProtocols: [proto])
                        }
                    }
                }
            }

            self.readPackets()
        }
    }

    /// Run one packet through the Rust engine. Returns the synthesized DNS
    /// reply, or nil when the packet is not a DNS query we answer.
    private func filter(_ packet: Data) -> Data? {
        var outBuf = [UInt8](repeating: 0, count: packet.count + 1500)
        let written = packet.withUnsafeBytes { rawIn -> Int in
            guard let inBase = rawIn.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return outBuf.withUnsafeMutableBufferPointer { outPtr in
                Int(aegis_process_ip_packet(inBase, packet.count,
                                            outPtr.baseAddress, outPtr.count))
            }
        }
        return written > 0 ? Data(outBuf.prefix(written)) : nil
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        // Stops the read loop re-arming and makes in-flight workers drop their
        // results instead of writing into a torn-down tunnel.
        running = false

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
