import Foundation
import Network
import NetworkExtension
import Security
import UIKit
import Darwin
import UserNotifications

enum NixelCheckState: String {
    case notChecked = "No verificado"
    case unavailable = "No disponible desde la API pública"
    case ready = "Listo"
}

struct NixelHybridDiagnostics {
    let deviceModel: String
    let systemVersion: String
    let jailbreakIndicator: String
    let tunnelStatus: String
    let tunnelConfigured: Bool
    let tunnelPluginPresent: Bool
    let pairing: NixelCheckState
    let developerMode: NixelCheckState

    var summary: String {
        let configured = tunnelConfigured ? "configurado" : "sin configurar"
        let plugin = tunnelPluginPresent ? "presente" : "ausente"
        return "Dispositivo local: \(deviceModel) · iOS/iPadOS \(systemVersion) · Jailbreak: \(jailbreakIndicator) · Túnel: \(tunnelStatus) (\(configured), extensión \(plugin)) · Pairing: \(pairing.rawValue) · Developer Mode: \(developerMode.rawValue)"
    }
}

enum NixelJailbreakEnvironment {
    static func indicator() -> String {
        let fm = FileManager.default
        let rootlessPaths = [
            "/var/jb",
            "/private/var/jb",
            "/var/containers/Bundle/jb"
        ]
        if let path = rootlessPaths.first(where: { fm.fileExists(atPath: $0) }) {
            return "indicio rootless visible (\(path)); falta confirmar estado"
        }
        let rootfulPaths = [
            "/usr/libexec/sshd",
            "/Library/MobileSubstrate/DynamicLibraries"
        ]
        if let path = rootfulPaths.first(where: { fm.fileExists(atPath: $0) }) {
            return "indicio rootful visible (\(path)); falta confirmar estado"
        }
        return "sin indicios visibles desde la app"
    }
}

enum NixelExploitPhase: String {
    case compatibilityCheck = "Comprobando compatibilidad"
    case developerModeRequired = "Developer Mode requerido"
    case kernelAccessPending = "Acceso al kernel pendiente"
    case kernelAccessActive = "Acceso al kernel verificado"
    case exploitReady = "Exploit compatible"
    case exploitUnavailable = "Exploit no integrado"
    case unsupported = "Sistema no verificado"
}

struct NixelExploitAssessment {
    let phase: NixelExploitPhase
    let system: String
    let environment: String
    let message: String

    var summary: String {
        "Exploit: \(phase.rawValue) · \(system) · \(environment) · \(message)"
    }
}

enum NixelExploitExecutionResult {
    case completed(String)
    case blocked(String)
}

struct NixelExploitPreflight {
    let pairingAuthenticated: Bool
    let developerModeEnabled: Bool
    let kernelAccessActive: Bool

    static let notReady = NixelExploitPreflight(
        pairingAuthenticated: false,
        developerModeEnabled: false,
        kernelAccessActive: false
    )

    var blockingReason: String? {
        if !pairingAuthenticated { return "Pairing autenticado pendiente." }
        if !developerModeEnabled { return "Developer Mode no confirmado." }
        if !kernelAccessActive { return "Acceso al kernel no verificado." }
        return nil
    }
}

protocol NixelExploitBackend {
    func execute(completion: @escaping (NixelExploitExecutionResult) -> Void)
}

/// Backend nulo hasta integrar una implementación compatible con el
/// dispositivo. Evita que la UI convierta una simulación en “Jailbreak”.
final class NixelUnavailableExploitBackend: NixelExploitBackend {
    func execute(completion: @escaping (NixelExploitExecutionResult) -> Void) {
        completion(.blocked("Backend de exploit no instalado."))
    }
}

/// Evalúa prerequisitos sin ejecutar código de exploit. El acceso al kernel
/// solo podrá pasar a activo mediante un backend verificado que devuelva una
/// señal explícita; no se infiere desde una carpeta, VPN o pairing.
enum NixelExploitCoordinator {
    static func assess() -> NixelExploitAssessment {
        let system = NyxelSupportPolicy.currentSystemDescription
        let environment = NixelJailbreakEnvironment.indicator()
        guard NyxelSupportPolicy.isCurrentSystemSupported else {
            return NixelExploitAssessment(
                phase: .unsupported,
                system: system,
                environment: environment,
                message: "La versión/build no está en la matriz verificada de Nyxel."
            )
        }
        return NixelExploitAssessment(
            phase: .exploitUnavailable,
            system: system,
            environment: environment,
            message: "El backend de exploit todavía no está integrado; no se ejecutó ninguna operación."
        )
    }

    static func execute(
        preflight: NixelExploitPreflight = .notReady,
        backend: NixelExploitBackend = NixelUnavailableExploitBackend(),
        completion: @escaping (NixelExploitExecutionResult) -> Void
    ) {
        let assessment = assess()
        if case .unsupported = assessment.phase {
            completion(.blocked(assessment.message))
            return
        }
        if let reason = preflight.blockingReason {
            completion(.blocked(reason))
            return
        }
        backend.execute(completion: completion)
    }
}

struct NixelRemotePairingService {
    let name: String
    let regType: String
    let endpoint: Network.NWEndpoint
}

enum NixelPairingProbeResult {
    case servicesFound([NixelRemotePairingService])
    case noService
    case unavailable(String)
}

enum NixelPairingTransportResult {
    case reachable(String)
    case unreachable(String)
}

/// Busca los anuncios Bonjour usados por Remote Pairing y comprueba el
/// alcance TCP del servicio. No solicita PIN, no guarda credenciales y no
/// afirma que el dispositivo esté emparejado o jailbroken.
final class NixelPairingProbe {
    static let shared = NixelPairingProbe()

    private var browsers: [NWBrowser] = []
    private var connection: NWConnection?
    private var timeoutWorkItem: DispatchWorkItem?
    private var completion: ((NixelPairingProbeResult) -> Void)?
    private var serviceMap: [String: NixelRemotePairingService] = [:]
    private let queue = DispatchQueue.main

    private init() {}

    func scan(timeout: TimeInterval = 8.0, completion: @escaping (NixelPairingProbeResult) -> Void) {
        stop()
        self.completion = completion
        serviceMap.removeAll()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let serviceTypes = [
            "_remotepairing-pairable-host._tcp",
            "_3105airlift._tcp"
        ]
        browsers = serviceTypes.map { serviceType in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint {
                        self.serviceMap[name] = NixelRemotePairingService(name: name, regType: serviceType, endpoint: result.endpoint)
                    }
                }
                if !self.serviceMap.isEmpty {
                    self.finish(.servicesFound(Array(self.serviceMap.values).sorted { $0.name < $1.name }))
                }
            }
            browser.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .failed(let error) = state {
                    self.finish(.unavailable(error.localizedDescription))
                }
            }
            browser.start(queue: queue)
            return browser
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.completion != nil else { return }
            if self.serviceMap.isEmpty {
                self.finish(.noService)
            }
        }
        timeoutWorkItem = work
        queue.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func probeTransport(
        service: NixelRemotePairingService,
        timeout: TimeInterval = 5.0,
        completion: @escaping (NixelPairingTransportResult) -> Void
    ) {
        connection?.cancel()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: service.endpoint, using: parameters)
        self.connection = connection
        var completed = false
        func finish(_ result: NixelPairingTransportResult) {
            guard !completed else { return }
            completed = true
            connection.cancel()
            self.connection = nil
            completion(result)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(.reachable(service.name))
            case .failed(let error):
                finish(.unreachable("\(service.name): \(error.localizedDescription)"))
            case .cancelled:
                finish(.unreachable("\(service.name): conexión cancelada"))
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) {
            finish(.unreachable("\(service.name): tiempo de conexión agotado"))
        }
    }

    func stop() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        connection?.cancel()
        connection = nil
        completion = nil
        serviceMap.removeAll()
    }

    private func finish(_ result: NixelPairingProbeResult) {
        guard let completion else { return }
        self.completion = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        completion(result)
    }
}

/// Guarda el registro de pairing como blob opaco en Keychain. El protocolo
/// que lo produce/consume se mantiene separado para no mezclar credenciales
/// con la UI o con la configuración VPN.
final class NixelPairingRecordStore {
    static let shared = NixelPairingRecordStore()
    private let service = "com.apple.mobile.MobileHouseArrest.nyxel.pairing"

    private init() {}

    func save(_ record: Data, deviceID: String) throws {
        let account = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !record.isEmpty else { throw StoreError.invalidRecord }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = record
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    func load(deviceID: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func remove(deviceID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum StoreError: LocalizedError {
        case invalidRecord
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidRecord: return "Registro de pairing vacío o sin identificador de dispositivo."
            case .keychain(let status): return "Keychain rechazó el registro de pairing (\(status))."
            }
        }
    }
}

enum NixelPairingAuthenticationResult {
    case authenticated(record: Data)
    case rejected(String)
    case unavailable(String)
}

protocol NixelPairingAuthenticator {
    func authenticate(
        service: NixelRemotePairingService,
        pin: String,
        storedRecord: Data?,
        completion: @escaping (NixelPairingAuthenticationResult) -> Void
    )
}

final class NixelExternalPairingAuthenticator: NixelPairingAuthenticator {
    func authenticate(
        service: NixelRemotePairingService,
        pin: String,
        storedRecord: Data?,
        completion: @escaping (NixelPairingAuthenticationResult) -> Void
    ) {
        guard let storedRecord, !storedRecord.isEmpty else {
            completion(.unavailable("No existe un registro RPairing preparado para \(service.name)."))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = storedRecord.withUnsafeBytes { rawBuffer -> Int32 in
                guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -20 }
                return service.name.withCString { name in
                    service.regType.withCString { regType in
                        "2424".withCString { hostname in
                            pin.withCString { pinValue in
                                nyxel_pair_rppairing(name, regType, hostname, pinValue, base, storedRecord.count, nil)
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                if result == 0 {
                    completion(.authenticated(record: storedRecord))
                } else {
                    completion(.rejected("El túnel RPairing no se pudo completar (código \(result))."))
                }
            }
        }
    }
}

enum NixelPairingSessionState {
    case idle
    case searching
    case serviceDetected(String)
    case transportReachable(String)
    case pairingRecordFound(String)
    case pairingRequired(String)
    case paired(String)
    case developerModeRequired(String)
    case ready(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle: return "Pairing sin iniciar"
        case .searching: return "Solicitando acceso a la red local y preparando el host AirLift…"
        case .serviceDetected(let name): return "Host local publicado: \(name); esperando que el iPad lo detecte…"
        case .transportReachable(let name): return "Transporte accesible: \(name)"
        case .pairingRecordFound(let name): return "Registro local encontrado para \(name); autenticación pendiente"
        case .pairingRequired(let name): return name.hasPrefix("PIN") ? name : "Esperando confirmación de pairing para \(name)…"
        case .paired(let name): return "Pairing autenticado: \(name)"
        case .developerModeRequired(let name): return "Developer Mode requerido para \(name)"
        case .ready(let name): return "Dispositivo listo para la siguiente fase: \(name)"
        case .failed(let message): return message
        }
    }
}

/// Solicita el permiso de red local antes de publicar el PairableHost.
/// Sigue el preflight de test1-main: un listener y un browser Bonjour activos
/// durante un breve intervalo hacen que iOS presente el permiso en contexto.
private final class NixelPairingLocalNetworkAuthorization {
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var timeoutWorkItem: DispatchWorkItem?
    private var completion: (() -> Void)?

    func request(completion: @escaping () -> Void) {
        stop()
        self.completion = completion

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let listener = try? NWListener(using: parameters)
        listener?.service = NWListener.Service(name: "SupportPatchProbe", type: "_aircardprobe._tcp")
        listener?.newConnectionHandler = { $0.cancel() }
        self.listener = listener

        let browser = NWBrowser(for: .bonjour(type: "_aircardprobe._tcp", domain: nil), using: parameters)
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NyxelActivityLog.record("Pairing local-network preflight: browser failed — \(error.localizedDescription)")
            }
        }
        self.browser = browser
        listener?.start(queue: .main)
        browser.start(queue: .main)

        let work = DispatchWorkItem { [weak self] in self?.finishRequest() }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func stop() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        completion = nil
    }

    private func finishRequest() {
        guard let completion else { return }
        self.completion = nil
        timeoutWorkItem = nil
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        completion()
    }
}

/// Orquesta el flujo de External: publica primero un PairableHost local para
/// que el iPad lo descubra. El backend FFI acepta la conexión iniciada por iOS,
/// entrega el PIN y devuelve el registro RPairing solo tras un handshake real.
private enum NixelPairingPINNotification {
    private static let identifier = "nyxel.pairing.pin.2424"
    private static let lifetime: TimeInterval = 10

    static func show(pin: String) {
        guard (4...8).contains(pin.count), pin.allSatisfy({ $0.isNumber }) else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Código de Pairing"
        content.body = "PIN: \(pin). Introdúcelo en la solicitud de iOS."
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                NyxelActivityLog.record("Pairing 2424: no se pudo mostrar la notificación (\(error.localizedDescription))")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }
}

final class NixelPairingSession {
    static let shared = NixelPairingSession()
    private(set) var state: NixelPairingSessionState = .idle
    private var service: NixelRemotePairingService?
    private let authenticator: NixelPairingAuthenticator = NixelExternalPairingAuthenticator()
    private let localNetworkAuthorization = NixelPairingLocalNetworkAuthorization()
    private var hostObservers: [NSObjectProtocol] = []

    private init() {}

    func begin(onState: @escaping (NixelPairingSessionState) -> Void) {
        stop()
        update(.searching, onState: onState)
        let center = NotificationCenter.default
        hostObservers = [
            center.addObserver(forName: NSNotification.Name("NyxelPairingHostListenerReady"), object: nil, queue: .main) { [weak self] note in
                let name = note.userInfo?["name"] as? String ?? "2424"
                self?.update(.serviceDetected("listener NWListener listo para \(name); esperando registro mDNS"), onState: onState)
            },
            center.addObserver(forName: NSNotification.Name("NyxelPairingHostDiagnostic"), object: nil, queue: .main) { [weak self] note in
                let message = note.userInfo?["message"] as? String ?? "Diagnóstico AirLift sin detalle."
                self?.update(.serviceDetected("2424 — \(message)"), onState: onState)
            },
            center.addObserver(forName: NSNotification.Name("NyxelPairingHostReady"), object: nil, queue: .main) { [weak self] note in
                let name = note.userInfo?["name"] as? String ?? "2424"
                let message = note.userInfo?["message"] as? String ?? "Servicio mDNS AirLift registrado."
                self?.update(.serviceDetected("2424 (\(name)) — \(message)"), onState: onState)
            },
            center.addObserver(forName: NSNotification.Name("NyxelPairingPIN"), object: nil, queue: .main) { [weak self] note in
                let pin = note.userInfo?["pin"] as? String ?? ""
                NixelPairingPINNotification.show(pin: pin)
                self?.update(.pairingRequired("PIN recibido por AirLift: \(pin). Introdúcelo en el iPad."), onState: onState)
            },
            center.addObserver(forName: NSNotification.Name("NyxelPairingCompleted"), object: nil, queue: .main) { [weak self] note in
                guard let self, let record = note.userInfo?["record"] as? Data else { return }
                do {
                    try NixelPairingRecordStore.shared.save(record, deviceID: "2424")
                    self.update(.paired("2424"), onState: onState)
                    self.update(.ready("2424"), onState: onState)
                } catch {
                    self.update(.failed("No se pudo guardar el registro RPairing: \(error.localizedDescription)"), onState: onState)
                }
            },
            center.addObserver(forName: NSNotification.Name("NyxelPairingHostFailed"), object: nil, queue: .main) { [weak self] note in
                self?.update(.failed(note.userInfo?["message"] as? String ?? "Falló el host PairableHost."), onState: onState)
            }
        ]
        localNetworkAuthorization.request { [weak self] in
            guard let self else { return }
            NixelPairingKeepAlive.start()
            let result = "SupportPatch".withCString { name in
                "iPhone".withCString { model in nyxel_pairable_host_start(name, model) }
            }
            if result != 0 {
                self.update(.failed("No se pudo publicar el host Remote Pairing (código \(result))."), onState: onState)
            }
        }
    }

    func stop() {
        localNetworkAuthorization.stop()
        NixelPairingProbe.shared.stop()
        hostObservers.forEach { NotificationCenter.default.removeObserver($0) }
        hostObservers.removeAll()
        nyxel_pairable_host_stop()
        NixelPairingKeepAlive.stop()
        service = nil
        state = .idle
    }

    func submitPIN(_ pin: String, onState: @escaping (NixelPairingSessionState) -> Void) {
        guard let service else {
            update(.failed("No hay un servicio Remote Pairing seleccionado."), onState: onState)
            return
        }
        let normalized = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 4,
              normalized.count <= 8,
              normalized.allSatisfy({ $0.isNumber }) else {
            update(.failed("El PIN de pairing debe tener entre 4 y 8 dígitos."), onState: onState)
            return
        }
        // El PIN no se persiste. El adaptador debe devolver un registro
        // autenticado antes de que se pueda marcar la sesión como paired.
        let stored = NixelPairingRecordStore.shared.load(deviceID: service.name)
        authenticator.authenticate(service: service, pin: normalized, storedRecord: stored) { [weak self] result in
            guard let self else { return }
            switch result {
            case .authenticated(let record):
                do {
                    try NixelPairingRecordStore.shared.save(record, deviceID: "2424")
                    self.update(.paired("2424"), onState: onState)
                    self.update(.developerModeRequired("2424"), onState: onState)
                } catch {
                    self.update(.failed("No se pudo guardar el registro autenticado: \(error.localizedDescription)"), onState: onState)
                }
            case .rejected(let message):
                self.update(.failed("Pairing rechazado: \(message)"), onState: onState)
            case .unavailable(let message):
                self.update(.failed(message), onState: onState)
            }
        }
    }

    private func update(_ next: NixelPairingSessionState, onState: @escaping (NixelPairingSessionState) -> Void) {
        state = next
        NyxelActivityLog.record("Pairing: \(next.message)")
        onState(next)
    }
}

/// Punto único para el flujo Hybrid/Jailbreak.
///
/// La VPN es una dependencia de coordinación; una conexión exitosa no se
/// interpreta por sí sola como jailbreak exitoso. Pairing y Developer Mode
/// quedan expresamente sin verificar hasta integrar el transporte con el iPad.
enum NixelHybridCoordinator {
    private enum StartError: LocalizedError {
        case vpnStart(String)
        case vpnConnectionTimeout
        case rsdEndpointUnreachable(String)

        var errorDescription: String? {
            switch self {
            case .vpnStart(let detail):
                return "No se pudo iniciar el VPN local: \(detail). No se ejecutó la inyección."
            case .vpnConnectionTimeout:
                return "El VPN no llegó al estado Conectado dentro de 15 segundos. No se ejecutó la inyección."
            case .rsdEndpointUnreachable(let detail):
                return "AirLift no pudo abrir RSD por TCP 49152 en ninguno de sus endpoints (\(detail)). Confirma que el pairing terminó y que RSD está disponible; el estado VPN activo no garantiza que RSD responda. No se ejecutó la inyección."
            }
        }
    }

    // Keep the preflight in the same order as airlift-rust-core/src/exploit.rs.
    private static let rsdProbeHosts = ["127.0.0.1", "10.7.0.1", "10.7.0.2", "10.7.0.3"]

    static func diagnostics() -> NixelHybridDiagnostics {
        let device = UIDevice.current
        let vpn = NixelVPNManager.shared
        return NixelHybridDiagnostics(
            deviceModel: device.localizedModel,
            systemVersion: device.systemVersion,
            jailbreakIndicator: NixelJailbreakEnvironment.indicator(),
            tunnelStatus: NixelVPNManager.statusText(vpn.status),
            tunnelConfigured: vpn.isConfigured,
            tunnelPluginPresent: vpn.tunnelPluginPresent,
            pairing: .notChecked,
            developerMode: .notChecked
        )
    }

    static func start(completion: @escaping (Result<Void, Error>) -> Void) {
        let before = diagnostics()
        NyxelActivityLog.record("Hybrid diagnóstico: \(before.summary)")
        NyxelActivityLog.record(NixelExploitCoordinator.assess().summary)

        let vpn = NixelVPNManager.shared
        if vpn.status == .connected {
            completion(.success(()))
            return
        }
        if vpn.status == .connecting || vpn.status == .reasserting || vpn.status == .disconnecting {
            waitForVPNConnected(until: Date().addingTimeInterval(15), completion: completion)
            return
        }

        if isExternalVPNActive() {
            NyxelActivityLog.record("Hybrid VPN: VPN externo detectado; pairing puede continuar sin exigir RSD")
            completion(.success(()))
            return
        }

        let deadline = Date().addingTimeInterval(15)
        vpn.start { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    NyxelActivityLog.record("Hybrid VPN: solicitud aceptada; esperando estado Conectado")
                    waitForVPNConnected(until: deadline, completion: completion)
                case .failure(let error):
                    NyxelActivityLog.record("Hybrid VPN: error de inicio — \(error.localizedDescription)")
                    completion(.failure(StartError.vpnStart(error.localizedDescription)))
                }
            }
        }
    }

    /// El flujo de Developer Mode solo necesita que la preparación del VPN
    /// termine; RSD se valida después, en la ruta de inyección AirLift.
    static func startForAirLift(completion: @escaping (Result<Void, Error>) -> Void) {
        start { result in
            switch result {
            case .success:
                verifyRSDLoopback(completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func waitForVPNConnected(
        until deadline: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if NixelVPNManager.shared.status == .connected {
            completion(.success(()))
            return
        }
        guard Date() < deadline else {
            NyxelActivityLog.record("Hybrid VPN: no llegó a Conectado en 15s")
            completion(.failure(StartError.vpnConnectionTimeout))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            waitForVPNConnected(until: deadline, completion: completion)
        }
    }

    private static func verifyRSDLoopback(completion: @escaping (Result<Void, Error>) -> Void) {
        probeRSDLoopback(at: 0, failures: [], completion: completion)
    }

    private static func probeRSDLoopback(
        at index: Int,
        failures: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard index < rsdProbeHosts.count,
              let port = NWEndpoint.Port(rawValue: 49152) else {
            let detail = failures.joined(separator: "; ")
            NyxelActivityLog.record("Hybrid VPN: ningún endpoint RSD respondió: \(detail)")
            completion(.failure(StartError.rsdEndpointUnreachable(detail)))
            return
        }

        let host = rsdProbeHosts[index]
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        var finished = false
        let timeout = DispatchWorkItem {
            guard !finished else { return }
            finished = true
            connection.cancel()
            probeRSDLoopback(
                at: index + 1,
                failures: failures + ["\(host): timeout"],
                completion: completion
            )
        }

        connection.stateUpdateHandler = { state in
            guard !finished else { return }
            switch state {
            case .ready:
                finished = true
                timeout.cancel()
                connection.cancel()
                NyxelActivityLog.record("Hybrid VPN: endpoint RSD TCP 49152 reachable at \(host)")
                completion(.success(()))
            case .failed(let error):
                finished = true
                timeout.cancel()
                connection.cancel()
                let failure = "\(host): \(error.localizedDescription)"
                NyxelActivityLog.record("Hybrid VPN: probe RSD falló — \(failure)")
                probeRSDLoopback(
                    at: index + 1,
                    failures: failures + [failure],
                    completion: completion
                )
            default:
                break
            }
        }

        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: timeout)
    }

    static func isExternalVPNActive() -> Bool {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return false }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                NyxelActivityLog.record("VPN externo detectado en interfaz: \(name)")
                return true
            }
            cursor = ifa.pointee.ifa_next
        }
        return false
    }

    static func stop() {
        NixelPairingSession.shared.stop()
        NixelVPNManager.shared.stop()
    }

    static var status: NEVPNStatus {
        NixelVPNManager.shared.status
    }

    static var statusText: String {
        NixelVPNManager.statusText(status)
    }

    static var isActive: Bool {
        NixelVPNManager.shared.isActive
    }
}


// External publishes AirLift through Network.framework's NWListener.Service,
// not NSNetService. Accepted NWConnections are proxied to the local
// PairableHost socket consumed by the Rust FFI.
private final class NixelAirLiftNWPublisher {
    static let shared = NixelAirLiftNWPublisher()
    private let queue = DispatchQueue(label: "com.apple.mobile.MobileHouseArrest.airlift.listener")
    private var listener: NWListener?
    private var probeListener: NWListener?
    private var rawPort: UInt16 = 0
    private var advertisedName = ""
    private var sessions: [UUID: (NWConnection, NWConnection)] = [:]
    private let lock = NSLock()
    /// kDNSServiceErr_DefunctConnection: mDNSResponder todavía no cerró la
    /// sesión XPC del listener anterior. Crear un NWListener nuevo de
    /// inmediato (p. ej. al tocar "Reintentar") produce este error aunque
    /// el servicio esté bien formado. Hay que esperar a que cancel()
    /// termine antes de volver a publicar.
    private var pendingTeardown: DispatchWorkItem?
    private var retriedAfterDefunct = false

    func start(name: String, rawPort: UInt16, txtRecord: Data) {
        pendingTeardown?.cancel()
        let hadActiveListener = listener != nil || probeListener != nil
        teardown()
        self.rawPort = rawPort
        self.advertisedName = name
        self.retriedAfterDefunct = false

        let work = DispatchWorkItem { [weak self] in
            self?.publish(name: name, txtRecord: txtRecord)
        }
        pendingTeardown = work
        // Si no había nada corriendo, no hace falta esperar la cancelación.
        queue.asyncAfter(deadline: .now() + (hadActiveListener ? 0.6 : 0), execute: work)
    }

    private func publish(name: String, txtRecord: Data) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        guard let listener = try? NWListener(using: parameters, on: .any) else {
            postFailure("NWListener no pudo crear el listener TCP.")
            return
        }
        listener.service = NWListener.Service(
            name: name,
            type: "_remotepairing-pairable-host._tcp",
            domain: nil,
            txtRecord: txtRecord
        )
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            guard let self else { return }
            switch change {
            case .add(.service(let name, let type, let domain, let interface)):
                self.postRegistered(name: name, type: type, domain: domain,
                                    interface: String(describing: interface))
            case .remove(.service(let name, let type, let domain, let interface)):
                self.postDiagnostic("Servicio mDNS retirado: \(name).\(type) en \(domain) (\(interface))")
            @unknown default:
                self.postDiagnostic("Cambio de registro mDNS no reconocido.")
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.postListenerReady()
                // Publicar los dos servicios a la vez compite por la misma
                // conexión XPC a mDNSResponder. Se espera a que el principal
                // esté listo antes de abrir el segundo.
                self.startProbeListener(parameters: parameters)
            case .failed(let error):
                self.handleFailure(error, label: "NWListener AirLift", name: name, txtRecord: txtRecord)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.proxy(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func startProbeListener(parameters: NWParameters) {
        let probeListener = try? NWListener(using: parameters, on: .any)
        probeListener?.service = NWListener.Service(
            name: "2424AirLiftProbe",
            type: "_3105airlift._tcp",
            domain: nil,
            txtRecord: nil
        )
        probeListener?.serviceRegistrationUpdateHandler = { [weak self] change in
            if case .add(.service(let name, let type, let domain, let interface)) = change {
                self?.postDiagnostic("Probe AirLift registrado: \(name).\(type) en \(domain) (\(interface)).")
            }
        }
        probeListener?.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.postDiagnostic("Probe AirLift no disponible: \(error.localizedDescription)")
            }
        }
        probeListener?.newConnectionHandler = { [weak self] connection in
            self?.postDiagnostic("Conexión recibida en el probe AirLift.")
            connection.cancel()
        }
        self.probeListener = probeListener
        probeListener?.start(queue: queue)
    }

    private func handleFailure(_ error: NWError, label: String, name: String, txtRecord: Data) {
        let isDefunct: Bool
        if case .dns(let code) = error, code == -65569 /* kDNSServiceErr_DefunctConnection */ {
            isDefunct = true
        } else {
            isDefunct = false
        }
        guard isDefunct, !retriedAfterDefunct else {
            postFailure("\(label) falló: \(error.localizedDescription)")
            return
        }
        // Error transitorio conocido: la sesión anterior con mDNSResponder
        // seguía viva. Un único reintento tras una pausa suele resolverlo.
        retriedAfterDefunct = true
        postDiagnostic("\(label): conexión XPC de mDNS caducada, reintentando…")
        listener?.cancel()
        probeListener?.cancel()
        queue.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.publish(name: name, txtRecord: txtRecord)
        }
    }

    private func teardown() {
        listener?.cancel()
        listener = nil
        probeListener?.cancel()
        probeListener = nil
        lock.lock()
        let active = sessions.values.flatMap { [$0.0, $0.1] }
        sessions.removeAll()
        lock.unlock()
        active.forEach { $0.cancel() }
    }

    func stop() {
        pendingTeardown?.cancel()
        pendingTeardown = nil
        teardown()
        rawPort = 0
    }

    private func proxy(_ incoming: NWConnection) {
        guard rawPort != 0, let port = NWEndpoint.Port(rawValue: rawPort) else {
            incoming.cancel()
            return
        }
        let local = NWConnection(host: NWEndpoint.Host("127.0.0.1"), port: port, using: .tcp)
        let id = UUID()
        lock.lock()
        sessions[id] = (incoming, local)
        lock.unlock()
        incoming.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.postDiagnostic("Conexión entrante AirLift lista; iniciando proxy al PairableHost.")
            case .failed(let error):
                self?.postFailure("Conexión AirLift falló: \(error.localizedDescription)")
                self?.finish(id)
            default:
                break
            }
        }
        local.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.postDiagnostic("Proxy local conectado al socket PairableHost.")
            case .failed(let error):
                self?.postFailure("Proxy local PairableHost falló: \(error.localizedDescription)")
                self?.finish(id)
            default:
                break
            }
        }
        incoming.start(queue: queue)
        local.start(queue: queue)
        pump(incoming, to: local, id: id)
        pump(local, to: incoming, id: id)
    }

    private func pump(_ source: NWConnection, to destination: NWConnection, id: UUID) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil { self.finish(id) }
                })
            }
            if isComplete || error != nil {
                self.finish(id)
            } else {
                self.pump(source, to: destination, id: id)
            }
        }
    }

    private func finish(_ id: UUID) {
        lock.lock()
        guard let pair = sessions.removeValue(forKey: id) else { lock.unlock(); return }
        lock.unlock()
        pair.0.cancel()
        pair.1.cancel()
    }

    private func postListenerReady() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("NyxelPairingHostListenerReady"),
                object: nil,
                userInfo: ["name": self.advertisedName]
            )
        }
    }

    private func postRegistered(name: String, type: String, domain: String, interface: String) {
        let message = "Servicio mDNS registrado: \(name).\(type) en \(domain) (\(interface))."
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("NyxelPairingHostRegistered"),
                object: nil,
                userInfo: ["name": name, "type": type, "domain": domain,
                           "interface": interface, "visibleName": self.advertisedName,
                           "message": message]
            )
            NotificationCenter.default.post(
                name: NSNotification.Name("NyxelPairingHostReady"),
                object: nil,
                userInfo: ["name": self.advertisedName, "instance": name,
                           "type": type, "domain": domain, "interface": interface,
                           "message": "External visible: \(self.advertisedName). \(message)"]
            )
        }
    }

    private func postDiagnostic(_ message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("NyxelPairingHostDiagnostic"),
                object: nil,
                userInfo: ["message": message]
            )
        }
    }

    private func postFailure(_ message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("NyxelPairingHostFailed"),
                object: nil,
                userInfo: ["message": message]
            )
        }
    }
}

@_cdecl("nyxel_nw_listener_start")
func nyxel_nw_listener_start(_ serviceName: UnsafePointer<CChar>?, _ rawPort: UInt16,
                                     _ txt: UnsafePointer<UInt8>?, _ txtLen: Int) {
    guard let serviceName, let txt, txtLen > 0 else { return }
    let name = String(cString: serviceName)
    let data = Data(bytes: txt, count: txtLen)
    NixelAirLiftNWPublisher.shared.start(name: name, rawPort: rawPort, txtRecord: data)
}

@_cdecl("nyxel_nw_listener_stop")
func nyxel_nw_listener_stop() {
    NixelAirLiftNWPublisher.shared.stop()
}
