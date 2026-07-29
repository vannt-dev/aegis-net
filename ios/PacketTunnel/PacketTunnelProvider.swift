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

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
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
            self?.readPackets()
        }
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
        completionHandler()
    }
}
