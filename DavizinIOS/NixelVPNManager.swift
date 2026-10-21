import Foundation
import NetworkExtension

/// Controla el túnel local que acompaña al modo Hybrid de Nixel External.
/// La autorización real depende de que Apple permita Network Extension al perfil
/// de firma; sin ese entitlement iOS no puede crear la configuración VPN.
final class NixelVPNManager: NSObject {
    static let shared = NixelVPNManager()
    static let tunnelBundleIdentifier = "com.apple.mobile.MobileHouseArrest.ExternalTunnel"

    private(set) var manager: NETunnelProviderManager?
    private(set) var lastError: Error?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(statusChanged), name: .NEVPNStatusDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var status: NEVPNStatus { manager?.connection.status ?? .invalid }
    var isActive: Bool { status == .connected || status == .connecting || status == .reasserting }
    var isConfigured: Bool { manager != nil }
    var tunnelPluginPresent: Bool {
        guard let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ExternalTunnel.appex") else { return false }
        return (try? url.checkResourceIsReachable()) ?? false
    }

    func load(completion: @escaping (Result<Void, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error { self?.lastError = error; completion(.failure(error)); return }
            let existing = managers?.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.tunnelBundleIdentifier }
            self?.manager = existing ?? NETunnelProviderManager()
            completion(.success(()))
        }
    }

    func installOrUpdate(completion: @escaping (Result<Void, Error>) -> Void) {
        load { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                let m = self.manager ?? NETunnelProviderManager()
                let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
                proto.providerBundleIdentifier = Self.tunnelBundleIdentifier
                proto.serverAddress = "10.7.0.1"
                proto.providerConfiguration = [
                    "TunnelIfaceIP": "10.7.1.1/32",
                    "TunnelPeerIP": "10.7.0.1/32",
                    "HybridMode": true
                ]
                proto.includeAllNetworks = false
                // Keep the system's primary route (including cellular data) in control.
                proto.enforceRoutes = false
                m.protocolConfiguration = proto
                m.localizedDescription = "Nixel External Hybrid"
                m.isEnabled = true
                m.saveToPreferences { error in
                    if let error { self.lastError = error; completion(.failure(error)) }
                    else { self.manager = m; completion(.success(())) }
                }
            }
        }
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        installOrUpdate { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                do { try self.manager?.connection.startVPNTunnel(); completion(.success(())) }
                catch { self.lastError = error; completion(.failure(error)) }
            }
        }
    }

    func stop() { manager?.connection.stopVPNTunnel() }

    @objc private func statusChanged() {
        NyxelActivityLog.record("Hybrid VPN: \(Self.statusText(status))")
    }

    static func statusText(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected: return "Conectado"
        case .connecting: return "Conectando"
        case .reasserting: return "Reconectando"
        case .disconnecting: return "Desconectando"
        case .disconnected: return "Desconectado"
        default: return "No configurado"
        }
    }
}
