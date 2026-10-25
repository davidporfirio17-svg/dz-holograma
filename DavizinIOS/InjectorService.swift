import Foundation
import CryptoKit

struct InjectorResult {
    let success: Bool
    let message: String
}

// MARK: - Injection diagnostics (log only)
fileprivate func sendErrorNotification(_ title: String, _ body: String) {
    NyxelActivityLog.record("\(title): \(body)")
}

private final class MCMContainerLookupResult {
    private let lock = NSLock()
    private var storedPath: String?
    private var storedError: String?

    func store(path: String?, error: String?) {
        lock.lock()
        storedPath = path
        storedError = error
        lock.unlock()
    }

    func snapshot() -> (path: String?, error: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (storedPath, storedError)
    }
}

// Carpeta base donde vive el archivo dentro del contenedor de Free Fire.
private let kBaseFolder = "Documents/contentcache/Compulsory/ios/gameassetbundles/avatar"
private var kConfigURL: String { "https://" + NyxelStringShield.workerHost + NyxelStringShield.pathAppConfig }

// Valores originales: se conservan como respaldo si el Worker no responde.
private func defaultDestFileName(for game: DavizinGame) -> String {
    switch game {
    case .freeFireMax:
        return "assetindexer.PENojQAQf9a1l6Dzjs0n1Z3rtVU~3D"
    case .freeFire:
        return "assetindexer.H5ak1JM1Eck~2FxRcJrEp~2FMzeuqmY~3D"
    }
}

private func isSafeAssetFileName(_ value: String) -> Bool {
    guard value.hasPrefix("assetindexer."), value.count <= 180 else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~-=")
    return !value.isEmpty && value.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func savedDestFileName(for game: DavizinGame) -> String {
    let key = game == .freeFireMax ? "dz_active_dest_max" : "dz_active_dest_normal"
    if let saved = UserDefaults.standard.string(forKey: key), isSafeAssetFileName(saved) { return saved }
    return defaultDestFileName(for: game)
}

private func isSafeRelativePath(_ value: String) -> Bool {
    guard value.hasPrefix("Documents/"), value.count <= 240, !value.contains(".."), !value.contains("//") else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~/-=")
    return value.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func destPathRel(for game: DavizinGame, mode: DavizinMode) -> String {
    let configured = game == .freeFireMax ? mode.pathMax : mode.pathNormal
    if let configured, isSafeRelativePath(configured) { return configured }
    return kBaseFolder + "/" + savedDestFileName(for: game)
}

private func activePathKey(for game: DavizinGame) -> String {
    return game == .freeFireMax ? "dz_active_path_max" : "dz_active_path_normal"
}

private func originalMissingKey(for game: DavizinGame) -> String {
    return game == .freeFireMax ? "dz_original_missing_max" : "dz_original_missing_normal"
}

private func restoreCompletedKey(for game: DavizinGame) -> String {
    return game == .freeFireMax ? "dz_restore_completed_max" : "dz_restore_completed_normal"
}

private func legacyDestPathRel(for game: DavizinGame) -> String {
    return kBaseFolder + "/" + savedDestFileName(for: game)
}

private func backPathRel(for game: DavizinGame, mode: DavizinMode) -> String {
    return disguisedBackupPath(for: destPathRel(for: game, mode: mode))
}

private func disguisedBackupPath(for relPath: String) -> String {
    let folder = (relPath as NSString).deletingLastPathComponent
    let digest = SHA256.hash(data: Data(relPath.utf8))
    let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
    let disguisedName = "assetindexer." + String(hex.prefix(28))
    return folder.isEmpty ? disguisedName : folder + "/" + disguisedName
}

private func requiresPairingTransportOnCurrentDevice() -> Bool {
    let device = NyxelDeviceInfo.versionTuple
    return NyxelSupportPolicy.requiresPairingTunnel(
        major: device.major,
        minor: device.minor,
        patch: device.patch,
        build: NyxelSupportPolicy.currentBuild
    )
}

// Base del Worker que sirve los cache_res desde KV.
private var kCacheBaseURL: String { "https://" + NyxelStringShield.workerHost }

class InjectorService {
    private static let mcmLookupQueue = DispatchQueue(label: "com.davizin.mcm-container-lookup", qos: .userInitiated)

    /// Bundle ID del contenedor segun el juego.
    private static func bundleID(for game: DavizinGame) -> String {
        switch game {
        case .freeFireMax: return "com.dts.freefiremax"
        case .freeFire:    return "com.dts.freefireth"
        }
    }

    // MARK: - MCM Container Lookup (with timeout)

    private static func getContainerPathWithTimeout(bundleID: String, timeout: TimeInterval = 15, error: inout String?) -> String? {
        let completed = DispatchSemaphore(value: 0)
        let result = MCMContainerLookupResult()
        mcmLookupQueue.async {
            var lookupError: NSString?
            let path = DavizinGetContainerPath(bundleID, &lookupError)
            result.store(path: path as String?, error: lookupError as String?)
            completed.signal()
        }

        guard completed.wait(timeout: .now() + timeout) == .success else {
            error = "MCM container lookup timed out after \(Int(timeout)) seconds"
            NyxelActivityLog.record("PASO 3: MCM timeout tras \(Int(timeout))s; se cancela antes de inyectar")
            return nil
        }
        let value = result.snapshot()
        error = value.error
        return value.path
    }

    // MARK: - Dual-path container I/O (iOS 26 MCM directo / iOS 27 AirLift)

    private struct ContainerWriteError: LocalizedError {
        let airliftNote: String
        let directError: Swift.Error
        var errorDescription: String? { "\(directError.localizedDescription) [\(airliftNote)]" }
    }

    /// Escribe datos en el contenedor del juego.
    /// iOS 27+: usa AirLift (pairing + RSD tunnel).
    /// iOS <= 26: intenta AirLift si hay pairing disponible, si no cae a MCM + file I/O directo.
    private static func writeToContainer(_ data: Data, relPath: String, container: String, bundleID: String) -> Swift.Error? {
        let fullPath = container + "/" + relPath
        let parentDir = (fullPath as NSString).deletingLastPathComponent
        let pairingRequired = requiresPairingTransportOnCurrentDevice()

        NyxelActivityLog.record("DIAG writeToContainer relPath=\(relPath) pairingRequired=\(pairingRequired) airLiftAvailable=\(NixelAirLiftFileChannel.isAvailable)")

        // --- iOS 27+: AirLift es obligatorio ---
        if pairingRequired {
            guard NixelAirLiftFileChannel.isAvailable else {
                return ContainerWriteError(
                    airliftNote: "iOS 27 requiere un registro de pairing y tunel AirLift activos",
                    directError: NSError(domain: "Davizin", code: -27, userInfo: [
                        NSLocalizedDescriptionKey: "No hay un canal AirLift disponible para iOS 27."
                    ])
                )
            }
            switch NixelAirLiftFileChannel.write(data, toRelativePath: relPath, bundleID: bundleID) {
            case .success:
                return nil
            case .failure(let error):
                NyxelActivityLog.record("AirLift write fallo (\(relPath)): \(error.message)")
                return ContainerWriteError(airliftNote: "AirLift fallo: \(error.message)", directError: error)
            }
        }

        // --- iOS <= 26: intentar AirLift como optimizacion, fallback a MCM directo ---
        let handleRoot = DavizinGrantContainerAccess(container)
        let handleDir = DavizinGrantContainerAccess(parentDir)
        let handleFile = DavizinGrantContainerAccess(fullPath)
        defer {
            DavizinReleaseContainerGrant(handleFile)
            DavizinReleaseContainerGrant(handleDir)
            DavizinReleaseContainerGrant(handleRoot)
        }

        var airliftNote = "AirLift: sin registro de pairing guardado"
        if NixelAirLiftFileChannel.isAvailable {
            switch NixelAirLiftFileChannel.write(data, toRelativePath: relPath, bundleID: bundleID) {
            case .success: return nil
            case .failure(let error):
                airliftNote = "AirLift fallo: \(error.message)"
                NyxelActivityLog.record("AirLift write fallo (\(relPath)): \(error.message); usando metodo directo")
            }
        }

        let url = URL(fileURLWithPath: fullPath)
        do {
            try data.write(to: url, options: [])
            return nil
        } catch {
            do {
                try data.write(to: url, options: .atomic)
                return nil
            } catch let atomicError {
                return ContainerWriteError(airliftNote: airliftNote, directError: atomicError)
            }
        }
    }

    /// Lee datos del contenedor del juego.
    /// iOS 27+: usa AirLift.
    /// iOS <= 26: intenta AirLift si hay pairing disponible, si no cae a lectura directa.
    private static func readFromContainer(
        relPath: String,
        container: String,
        bundleID: String,
        onFailure: ((String) -> Void)? = nil
    ) -> Data? {
        let fullPath = container + "/" + relPath
        let parentDir = (fullPath as NSString).deletingLastPathComponent
        let pairingRequired = requiresPairingTransportOnCurrentDevice()

        NyxelActivityLog.record("DIAG readFromContainer relPath=\(relPath) pairingRequired=\(pairingRequired)")

        // --- iOS 27+: AirLift obligatorio ---
        if pairingRequired {
            guard NixelAirLiftFileChannel.isAvailable else {
                let detail = "AirLift read omitido: falta pairing requerido"
                NyxelActivityLog.record("DIAG \(detail)")
                onFailure?(detail)
                return nil
            }
            switch NixelAirLiftFileChannel.read(relativePath: relPath, bundleID: bundleID) {
            case .success(let data):
                NyxelActivityLog.record("DIAG read succeeded via AirLift bytes=\(data.count)")
                return data
            case .failure(let error):
                NyxelActivityLog.record("DIAG AirLift read failed relPath=\(relPath) detail=\(error.message)")
                onFailure?(error.message)
                return nil
            }
        }

        // --- iOS <= 26: intentar AirLift, fallback a lectura directa ---
        if NixelAirLiftFileChannel.isAvailable {
            switch NixelAirLiftFileChannel.read(relativePath: relPath, bundleID: bundleID) {
            case .success(let data):
                NyxelActivityLog.record("DIAG read succeeded via AirLift bytes=\(data.count)")
                return data
            case .failure(let error):
                NyxelActivityLog.record("DIAG AirLift read failed, falling back to direct: \(error.message)")
            }
        }

        let handleRoot = DavizinGrantContainerAccess(container)
        let handleDir = DavizinGrantContainerAccess(parentDir)
        let handleFile = DavizinGrantContainerAccess(fullPath)
        defer {
            DavizinReleaseContainerGrant(handleFile)
            DavizinReleaseContainerGrant(handleDir)
            DavizinReleaseContainerGrant(handleRoot)
        }

        let url = URL(fileURLWithPath: fullPath)
        do {
            let data = try Data(contentsOf: url)
            NyxelActivityLog.record("DIAG read succeeded via direct I/O bytes=\(data.count)")
            return data
        } catch {
            NyxelActivityLog.record("DIAG direct read failed relPath=\(relPath) error=\(error.localizedDescription)")
            onFailure?(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Bundle availability check

    static func isBundleAvailable(for game: DavizinGame) -> Bool {
        guard NyxelSupportPolicy.isCurrentSystemSupported else { return false }
        if requiresPairingTransportOnCurrentDevice() {
            return NixelAirLiftFileChannel.isAvailable
        }
        var error: NSString?
        guard let container = DavizinGetContainerPath(bundleID(for: game), &error) else { return false }
        return FileManager.default.fileExists(atPath: container)
    }

    // MARK: - Remote resource download

    private static func remoteSlot(for mode: DavizinMode, game: DavizinGame) -> String {
        return game == .freeFire ? mode.id + "_ff" : mode.id
    }

    private static func cacheKey(session: String) -> SymmetricKey {
        let material = Data(("dzcache:session:" + session).utf8)
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }

    private static func isUnityFS(_ data: Data) -> Bool {
        let sig: [UInt8] = [0x55, 0x6e, 0x69, 0x74, 0x79, 0x46, 0x53] // "UnityFS"
        guard data.count >= sig.count else { return false }
        return Array(data.prefix(sig.count)) == sig
    }

    private static func decrypt(_ blob: Data, session: String) -> Data? {
        guard blob.count > 12 + 16 else { return nil }
        let clean = Data(blob)
        let nonceData = clean.prefix(12)
        let tagData = clean.suffix(16)
        let cipherData = clean.dropFirst(12).dropLast(16)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(nonce: nonce,
                                               ciphertext: Data(cipherData),
                                               tag: Data(tagData))
            let plain = try AES.GCM.open(sealed, using: cacheKey(session: session))
            return plain
        } catch {
            return nil
        }
    }

    private static func refreshDestinationFileName(for game: DavizinGame, key: String, hwid: String) {
        guard let url = URL(string: kConfigURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: NyxelStringShield.headerKey)
        request.setValue(hwid, forHTTPHeaderField: NyxelStringShield.headerHWID)
        KeyValidator.applySecurityHeaders(to: &request)
        request.timeoutInterval = 8
        let semaphore = DispatchSemaphore(value: 0)
        NyxelCertPinning.shared.session.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let destinations = json["destinations"] as? [String: String] else { return }
            let name = game == .freeFireMax ? destinations["freeFireMax"] : destinations["freeFire"]
            guard let candidate = name, isSafeAssetFileName(candidate) else { return }
            let defaultsKey = game == .freeFireMax ? "dz_active_dest_max" : "dz_active_dest_normal"
            UserDefaults.standard.set(candidate, forKey: defaultsKey)
        }.resume()
        _ = semaphore.wait(timeout: .now() + 9)
    }

    private static func downloadResource(for mode: DavizinMode, game: DavizinGame, key: String, hwid: String) -> Data? {
        guard !key.isEmpty else { return nil }
        guard let session = KeyValidator.currentSessionToken, !session.isEmpty else { return nil }
        guard let url = URL(string: "\(kCacheBaseURL)/avatar/\(remoteSlot(for: mode, game: game))") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: NyxelStringShield.headerKey)
        request.setValue(hwid, forHTTPHeaderField: NyxelStringShield.headerHWID)
        KeyValidator.applySecurityHeaders(to: &request)
        request.timeoutInterval = 20

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?

        let task = NyxelCertPinning.shared.session.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let data = data, data.count > 28 else { return }

            if let plain = decrypt(data, session: session), plain.count > 0 {
                result = plain
            } else {
                result = nil
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 22)
        return result
    }

    static func checkIsInjected(bundleID: String) -> Bool {
        var err: NSString?
        guard let container = DavizinGetContainerPath(bundleID, &err) else { return false }
        return FileManager.default.fileExists(atPath: container + "/" + kBaseFolder)
    }

    // MARK: - Injection (dual-path: iOS 26 MCM directo / iOS 27 AirLift)

    static func inject(game: DavizinGame, mode: DavizinMode, key: String, hwid: String) -> InjectorResult {
        guard NyxelSupportPolicy.isCurrentSystemSupported else {
            return InjectorResult(
                success: false,
                message: "Version no verificada: \(NyxelSupportPolicy.currentSystemDescription)"
            )
        }

        let fm = FileManager.default
        let bid = bundleID(for: game)
        let pairingRequired = requiresPairingTransportOnCurrentDevice()

        NyxelActivityLog.record("========== INJECTION TRACE BEGIN ==========")
        NyxelActivityLog.record("DIAG system=\(NyxelSupportPolicy.currentSystemDescription) game=\(game.rawValue) mode=\(mode.displayName) pairingRequired=\(pairingRequired) airLiftAvailable=\(NixelAirLiftFileChannel.isAvailable)")

        // --- Resolver contenedor MCM ---
        var mcmErr: String?
        let container = getContainerPathWithTimeout(bundleID: bid, error: &mcmErr)

        if container == nil && pairingRequired && NixelAirLiftFileChannel.isAvailable {
            NyxelActivityLog.record("DIAG MCM lookup fallo en iOS 27 pero AirLift disponible; continuando sin container local")
        } else if container == nil {
            return InjectorResult(success: false,
                message: mcmErr ?? "Container no encontrado")
        }

        Self.refreshDestinationFileName(for: game, key: key, hwid: hwid)

        NotificationCenter.default.post(name: .nyxelInjectionProgress, object: "Descargando recurso del Worker...")

        guard let finalData = downloadResource(for: mode, game: game, key: key, hwid: hwid),
              finalData.count > 1000 else {
            return InjectorResult(success: false,
                message: "No se pudo obtener el recurso. Revisa tu conexion e intentalo de nuevo.")
        }

        let activeRel = destPathRel(for: game, mode: mode)
        let backupRel = disguisedBackupPath(for: activeRel)
        UserDefaults.standard.set(activeRel, forKey: activePathKey(for: game))

        // --- Backup del archivo original (guardado en almacenamiento privado de la app) ---
        if let container = container {
            let destPath = container + "/" + activeRel
            let destDir = (destPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

            let privateBackupDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("NyxelBackups", isDirectory: true)
            try? fm.createDirectory(at: privateBackupDir, withIntermediateDirectories: true)
            let digest = SHA256.hash(data: Data(activeRel.utf8))
            let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
            let privateBackupURL = privateBackupDir.appendingPathComponent(String(hex.prefix(32)))

            let originalFileExists = fm.fileExists(atPath: destPath)
            if originalFileExists && !fm.fileExists(atPath: privateBackupURL.path) {
                NotificationCenter.default.post(name: .nyxelInjectionProgress, object: "Guardando respaldo del original...")
                if let original = readFromContainer(relPath: activeRel, container: container, bundleID: bid) {
                    do {
                        try original.write(to: privateBackupURL)
                    } catch {
                        return InjectorResult(success: false,
                            message: "Error haciendo backup: \(error.localizedDescription)")
                    }
                }
                UserDefaults.standard.set(false, forKey: originalMissingKey(for: game))
            } else if !originalFileExists {
                UserDefaults.standard.set(true, forKey: originalMissingKey(for: game))
            }
        } else {
            UserDefaults.standard.set(true, forKey: originalMissingKey(for: game))
        }

        // --- Escribir el recurso inyectado ---
        NotificationCenter.default.post(name: .nyxelInjectionProgress, object: "Inyectando \(mode.displayName)...")

        let containerForWrite = container ?? "/not-available"
        let writeError = writeToContainer(finalData, relPath: activeRel, container: containerForWrite, bundleID: bid)
        if let writeError = writeError {
            return InjectorResult(success: false,
                message: "Error al inyectar: \(writeError.localizedDescription)")
        }

        NyxelActivityLog.record("========== INJECTION TRACE END (success) ==========")

        return InjectorResult(success: true,
            message: "\(mode.displayName) inyectado con exito!")
    }

    // MARK: - Compatibility check

    enum Compat {
        case compatible
        case noGameInstalled
        case notCompatible
        case unsupportedSystem
    }

    static func checkCompatibility() -> Compat {
        guard NyxelSupportPolicy.isCurrentSystemSupported else {
            return .unsupportedSystem
        }

        if requiresPairingTransportOnCurrentDevice() {
            return NixelAirLiftFileChannel.isAvailable ? .compatible : .notCompatible
        }

        let fm = FileManager.default
        let bundles = ["com.dts.freefiremax", "com.dts.freefireth"]

        var algunInstalado = false
        for bid in bundles {
            var err: NSString?
            if let container = DavizinGetContainerPath(bid, &err) {
                if fm.fileExists(atPath: container) {
                    return .compatible
                }
                algunInstalado = true
            }
        }
        return algunInstalado ? .notCompatible : .noGameInstalled
    }
}
