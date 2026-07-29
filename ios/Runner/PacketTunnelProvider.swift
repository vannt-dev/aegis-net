import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        let dnsSettings = NEDNSSettings(servers: ["1.1.1.1"])
        dnsSettings.matchDomains = [""] // Intercept all DNS requests
        tunnelNetworkSettings.dnsSettings = dnsSettings
        
        setTunnelNetworkSettings(tunnelNetworkSettings) { error in
            if let error = error {
                completionHandler(error)
            } else {
                completionHandler(nil)
                self.readPackets()
            }
        }
    }
    
    private func readPackets() {
        packetFlow.readPackets { [weak self] (packets, protocols) in
            guard let self = self else { return }

            var outPackets: [Data] = []
            var outProtocols: [NSNumber] = []

            for (index, packet) in packets.enumerated() {
                // Hand each raw IPv4 packet to the Rust engine; a non-empty
                // result is a synthesized DNS reply to write straight back.
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

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
