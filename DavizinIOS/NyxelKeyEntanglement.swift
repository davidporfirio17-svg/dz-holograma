import Foundation
import CryptoKit

/// Entrelazado de la Key con el payload crítico.
///
/// En lugar de "si Key válida → inject(data), si no → mostrar error", acá la Key
/// se usa para **derivar material criptográfico** que valida consistencia del
/// propio código y de datos clave. Si un atacante parchea el check de autorización,
/// las validaciones derivadas aquí NO pasan y el flujo degrada silenciosamente.
///
/// Importante: todo esto vive en el iPad. No hay round-trip al Worker.
enum NyxelKeyEntanglement {

    /// Deriva un bloque de 32 bytes a partir de la Key, HWID y bundle version.
    /// Se usa como "fingerprint" de la autorización.
    static func derivedMaterial(key: String, hwid: String) -> Data {
        let bundle = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let input = "\(key)|\(hwid)|\(bundle)|nyxel-v1"
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest)
    }

    /// Checksum corto (8 bytes hex) para persistir con el estado de login.
    /// Permite re-validar que la Key en memoria no fue tocada.
    static func fingerprint(key: String, hwid: String) -> String {
        let m = derivedMaterial(key: key, hwid: hwid)
        return m.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Comprueba que `fingerprint` coincide con el que correspondería a `key`+`hwid`.
    /// Se usa en múltiples puntos del flujo de inyección — si cualquiera falla
    /// significa que la Key en memoria fue manipulada o el fingerprint se perdió.
    static func matches(fingerprint: String, key: String, hwid: String) -> Bool {
        let expected = self.fingerprint(key: key, hwid: hwid)
        // Comparación en tiempo constante para evitar timing attacks.
        guard expected.count == fingerprint.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(expected.utf8, fingerprint.utf8) {
            diff |= a ^ b
        }
        return diff == 0
    }
}

/// Store en memoria para el "token entrelazado" de la sesión actual.
/// Se escribe al validar la Key (login exitoso) y se lee en los chequeos
/// distribuidos por el código.
final class NyxelAuthorizationState {
    static let shared = NyxelAuthorizationState()
    private let lock = NSLock()
    private var _fingerprint: String?
    private var _key: String?
    private var _hwid: String?

    private init() {}

    func bind(key: String, hwid: String) {
        lock.lock(); defer { lock.unlock() }
        _key = key
        _hwid = hwid
        _fingerprint = NyxelKeyEntanglement.fingerprint(key: key, hwid: hwid)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        _key = nil
        _hwid = nil
        _fingerprint = nil
    }

    /// Devuelve true si la Key en memoria sigue siendo coherente con el
    /// fingerprint guardado al login. Si el atacante parcheó algo para
    /// forzar `_key = "whatever"` sin pasar por `bind`, aquí se cae.
    var isConsistent: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let fp = _fingerprint, let k = _key, let h = _hwid else { return false }
        return NyxelKeyEntanglement.matches(fingerprint: fp, key: k, hwid: h)
    }

    var fingerprint: String? {
        lock.lock(); defer { lock.unlock() }
        return _fingerprint
    }
}
