import Foundation

/// Estado de defensa compartido. Punto único donde se consulta "¿este runtime
/// es confiable?". Si no lo es, los puntos críticos del flujo degradan
/// silenciosamente en lugar de mostrar un error que delate al atacante qué
/// disparó la detección.
final class NyxelRuntimeState {
    static let shared = NyxelRuntimeState()
    private let lock = NSLock()
    private var _tamperCode: String?
    private var _integrityVerified: Bool = false

    private init() {}

    func markTampered(code: String) {
        lock.lock(); defer { lock.unlock() }
        if _tamperCode == nil { _tamperCode = code }
    }

    func markIntegrityVerified() {
        lock.lock(); defer { lock.unlock() }
        _integrityVerified = true
    }

    var isTampered: Bool {
        lock.lock(); defer { lock.unlock() }
        return _tamperCode != nil
    }

    /// Código corto para log diagnóstico. No se muestra en UI por diseño.
    var tamperCode: String? {
        lock.lock(); defer { lock.unlock() }
        return _tamperCode
    }

    /// Chequeo integrado que combina:
    ///  - resultado del inspect de arranque (anti-debug / anti-Frida)
    ///  - un re-inspect en caliente
    ///  - consistencia del fingerprint de autorización en memoria
    /// Usar antes de ejecutar operaciones críticas (kexploit, AirLift write).
    func isTrustedForCriticalOperation() -> Bool {
        if isTampered { return false }
        if NyxelAntiTamper.inspect().isSuspect { return false }
        if !NyxelAuthorizationState.shared.isConsistent { return false }
        return true
    }
}
