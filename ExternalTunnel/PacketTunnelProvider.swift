import NetworkExtension

/// Túnel local: el iPhone se habla a sí mismo a través de 10.7.0.1.
/// Cada paquete IPv4 vuelve por el mismo túnel con origen y destino intercambiados.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var interfaceAddress = "10.7.1.1"
    private var peerAddress = "10.7.0.1"

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        if let value = config["TunnelIfaceIP"] as? String, let ip = value.split(separator: "/").first { interfaceAddress = String(ip) }
        if let value = config["TunnelPeerIP"] as? String, let ip = value.split(separator: "/").first { peerAddress = String(ip) }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: peerAddress)
        let ipv4 = NEIPv4Settings(addresses: [interfaceAddress], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: peerAddress, subnetMask: "255.255.255.255")]
        ipv4.excludedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        setTunnelNetworkSettings(settings) { [weak self] error in
            if error == nil { self?.readLoop() }
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func readLoop() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            var out: [Data] = []
            for (index, packet) in packets.enumerated() {
                var data = packet
                if protocols[index].intValue == AF_INET, data.count >= 20 {
                    data.withUnsafeMutableBytes { raw in
                        let bytes = raw.bindMemory(to: UInt8.self)
                        for i in 0..<4 { bytes.swapAt(12 + i, 16 + i) }
                    }
                }
                out.append(data)
            }
            self.packetFlow.writePackets(out, withProtocols: protocols)
            self.readLoop()
        }
    }
}
