import Foundation
import UIKit
import Security

struct KeyResponse: Codable {
    let success: Bool
    let message: String?
    let error_code: String?
    let remaining_seconds: Int?
    let data: KeyData?
    let signature: String?
    let notice: String?
}

struct KeyData: Codable {
    let container_access_ready: Bool?
    let remaining_seconds: Int?
    let expire: Int64?
    let token: String?
    let resource_key: String?
    let tier: String?
    let modes: [DavizinMode]?
    let client_session: String?
    let country: String?
}

class KeyValidator {

    /// Token efímero emitido por el Worker para las operaciones posteriores.
    /// No se persiste en UserDefaults: debe desaparecer al cerrar la app.
    private(set) static var currentSessionToken: String?
    private(set) static var lastCountryCode: String?
    private(set) static var lastValidationWasVersionUnavailable = false

    private static let installationService = "com.davizin.client-installation"

    /// Identificador aleatorio por instalación, protegido por Keychain y no incluido en backups.
    static func getInstallationID() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: installationService,
            kSecAttrAccount as String: "installation-id",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        let value = UUID().uuidString.lowercased()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: installationService,
            kSecAttrAccount as String: "installation-id",
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(add as CFDictionary, nil)
        return value
    }

    static func getAppBuild() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Añade identidad de instalación, build y sesión a cada solicitud sensible.
    static func applySecurityHeaders(to request: inout URLRequest) {
        request.setValue(getInstallationID(), forHTTPHeaderField: "X-DZ-Installation")
        request.setValue(getAppBuild(), forHTTPHeaderField: "X-DZ-Build")
        if let session = currentSessionToken, !session.isEmpty {
            request.setValue(session, forHTTPHeaderField: "X-DZ-Session")
        }
    }

    static func getDeviceHWID() -> String {
        if let hwid = UIDevice.current.identifierForVendor?.uuidString {
            return hwid
        }
        return UUID().uuidString
    }

    static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = String(bytes: Data(bytes: &systemInfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "Unknown"
        return model
    }

    static func getIOSVersion() -> String {
        return UIDevice.current.systemVersion
    }

    static func validate(key: String, completion: @escaping (Bool, String, Int, String?) -> Void) {
        validateWithSeconds(key: key, completion: completion)
    }

    static func validateWithSeconds(key: String, completion: @escaping (Bool, String, Int, String?) -> Void) {
        // Check system compatibility before attempting key validation
        guard NyxelOperationGuard.canProceedWithKeyValidation() else {
            let errorMsg = "Sistema no soportado: \(NyxelSupportPolicy.currentSystemDescription)"
            nyxelLog("Key validation blocked: \(errorMsg)", level: "WARN")
            NyxelRemoteConfigStore.recordFailure("\(NyxelErrorCode.unsupportedSystem) — \(errorMsg)")
            completion(false, errorMsg, 0, nil)
            return
        }
        
        let serverURL = "https://dz-holograma.davidporfirio17.workers.dev"
        guard let url = URL(string: "\(serverURL)/check") else {
            completion(false, "URL inválida", 0, nil)
            return
        }

			var request = URLRequest(url: url)
			request.httpMethod = "POST"
			request.cachePolicy = .reloadIgnoringLocalCacheData
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
			request.timeoutInterval = 15
        applySecurityHeaders(to: &request)

        let hwid = getDeviceHWID()
        let model = getDeviceModel()
        let ios = getIOSVersion()
        let upperKey = key.uppercased()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let appBuild = getAppBuild()

        let body: [String: Any] = [
            "key": upperKey,
            "username": upperKey,
            "hwid": hwid,
            "model": model,
            "ios": ios,
            "app_version": appVersion,
            "app_build": appBuild,
            "installation_id": getInstallationID()
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        NSLog("[KeyValidator] Enviando validación — build=%@, version=%@", appBuild, appVersion)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
                NSLog("[KeyValidator] Respuesta HTTP %d", httpStatus)

                if let error = error {
                    NSLog("[KeyValidator] Error de red: %@", error.localizedDescription)
                    NyxelRemoteConfigStore.recordFailure("\(NyxelErrorCode.workerUnavailable) — \(error.localizedDescription)")
                    completion(false, "Error de conexión: \(error.localizedDescription)", 0, nil)
                    return
                }

                guard let data = data else {
                    NSLog("[KeyValidator] Sin datos en respuesta")
                    NyxelRemoteConfigStore.recordFailure("\(NyxelErrorCode.workerUnavailable) — Sin respuesta")
                    completion(false, "Sin respuesta del servidor", 0, nil)
                    return
                }

                let rawBody = String(data: data.prefix(512), encoding: .utf8) ?? "(no legible)"
                NSLog("[KeyValidator] Body: %@", rawBody)

                do {
                    let resp = try JSONDecoder().decode(KeyResponse.self, from: data)
                    lastCountryCode = resp.data?.country?.uppercased()
                    lastValidationWasVersionUnavailable = resp.error_code == "VERSION_UNAVAILABLE"
                    let rem = resp.data?.remaining_seconds ?? resp.remaining_seconds ?? 0

                    if resp.success {
                        let modes = resp.data?.modes ?? []
                        guard modes.count <= 64 else {
                            NyxelRemoteConfigStore.recordFailure("\(NyxelErrorCode.invalidConfiguration) — Demasiados modos")
                            completion(false, "Configuración inválida. Inténtalo más tarde.", 0, nil)
                            return
                        }
                        DavizinModeCatalog.save(modes)
                        guard let session = resp.data?.client_session, !session.isEmpty else {
                            NyxelRemoteConfigStore.recordFailure("\(NyxelErrorCode.invalidConfiguration) — Sesión ausente")
                            completion(false, "Respuesta incompleta. Servidor no autorizado.", 0, nil)
                            return
                        }
                        currentSessionToken = session
                        NyxelRemoteConfigStore.recordAccepted()
                        NSLog("[KeyValidator] Login exitoso — %d modos, %d seg restantes", modes.count, rem)
                    } else {
                        currentSessionToken = nil
                        NSLog("[KeyValidator] Login rechazado — error_code=%@, message=%@",
                              resp.error_code ?? "(nil)", resp.message ?? "(nil)")
                    }

                    completion(resp.success, resp.message ?? "ok", rem, resp.notice)
                } catch {
                    NSLog("[KeyValidator] JSON decode error: %@", "\(error)")
                    lastValidationWasVersionUnavailable = false
                    NyxelRemoteConfigStore.recordFailure("\(NyxelErrorCode.invalidConfiguration) — Respuesta no válida")
                    completion(false, "Error al procesar respuesta del servidor", 0, nil)
                }
            }
        }.resume()
    }
}
