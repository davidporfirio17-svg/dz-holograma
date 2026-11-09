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

private func isSafeBundleFileName(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 200,
          !value.contains("/"), !value.contains("\\"), !value.contains(".."),
          !value.hasPrefix(".") else { return false }
    let blocked = CharacterSet(charactersIn: "\0\u{01}\u{02}\u{03}\u{04}\u{05}\u{06}\u{07}\u{08}\u{09}\u{0a}\u{0b}\u{0c}\u{0d}\u{0e}\u{0f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f}<>:\"|?*")
    return !value.unicodeScalars.contains { blocked.contains($0) }
}

private func bundleBasePath(for game: DavizinGame, mode: DavizinMode) -> String? {
    let configured = game == .freeFireMax ? mode.pathMax : mode.pathNormal
    guard let configured, isSafeRelativePath(configured) else { return nil }
    return configured
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

    // MARK: - POSIX directory creation (bypass Foundation for cross-container writes)

    /// Creates a directory tree one level at a time using POSIX mkdir.
    /// Returns true if the full path exists (created or already existed).
    private static func ensureDirectoryTree(_ path: String) -> Bool {
        var current = ""
        for comp in path.split(separator: "/", omittingEmptySubsequences: true) {
            current += "/" + String(comp)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: current, isDirectory: &isDir) {
                if isDir.boolValue { continue }
                NyxelActivityLog.record("MKDIR bloqueado: '\(comp)' existe pero no es directorio")
                return false
            }
            let rc = current.withCString { mkdir($0, S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) }
            if rc != 0 {
                let e = errno
                if e == EEXIST { continue }
                NyxelActivityLog.record("MKDIR fallo '\(comp)': errno=\(e) \(String(cString: strerror(e)))")
                return false
            }
        }
        return true
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

        _ = ensureDirectoryTree(parentDir)

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
                var isDir: ObjCBool = false
                let pdOk = FileManager.default.fileExists(atPath: parentDir, isDirectory: &isDir)
                NyxelActivityLog.record("WRITE Foundation fallo code=\((atomicError as NSError).code) parentOk=\(pdOk && isDir.boolValue) sz=\(data.count) — POSIX fallback")
                let fd = fullPath.withCString { open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o644) }
                if fd >= 0 {
                    let ok = data.withUnsafeBytes { buf -> Bool in
                        guard let p = buf.baseAddress else { return false }
                        return Darwin.write(fd, p, buf.count) == buf.count
                    }
                    close(fd)
                    if ok { return nil }
                    NyxelActivityLog.record("WRITE POSIX parcial errno=\(errno)")
                } else {
                    NyxelActivityLog.record("WRITE POSIX open fallo errno=\(errno) \(String(cString: strerror(errno)))")
                }
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
        UserDefaults.standard.set(activeRel, forKey: activePathKey(for: game))

        if let container = container {
            let destPath = container + "/" + activeRel
            let destDir = (destPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        }

        // --- Escribir el recurso inyectado (reemplazo directo, sin backup) ---
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

    // MARK: - Bundle Injection (multi-file, direct replacement, no backup)

    private struct BundleManifest: Codable {
        let files: [String]
    }

    static func injectBundle(game: DavizinGame, mode: DavizinMode, key: String, hwid: String) -> InjectorResult {
        guard NyxelSupportPolicy.isCurrentSystemSupported else {
            return InjectorResult(success: false,
                message: "Version no verificada: \(NyxelSupportPolicy.currentSystemDescription)")
        }

        let bid = bundleID(for: game)
        let pairingRequired = requiresPairingTransportOnCurrentDevice()

        let sessionToken = KeyValidator.currentSessionToken ?? ""
        NyxelActivityLog.record("========== BUNDLE INJECTION TRACE BEGIN ==========")
        NyxelActivityLog.record("DIAG system=\(NyxelSupportPolicy.currentSystemDescription) game=\(game.rawValue) mode=\(mode.displayName) bundle=true pairingRequired=\(pairingRequired) session=\(sessionToken.isEmpty ? "VACIO" : "ok(\(sessionToken.prefix(8)))")")

        var mcmErr: String?
        let container = getContainerPathWithTimeout(bundleID: bid, error: &mcmErr)

        if container == nil && pairingRequired && NixelAirLiftFileChannel.isAvailable {
            NyxelActivityLog.record("DIAG MCM fallo en iOS 27 pero AirLift disponible; continuando")
        } else if container == nil {
            return InjectorResult(success: false,
                message: mcmErr ?? "Container no encontrado")
        }

        guard let basePath = bundleBasePath(for: game, mode: mode) else {
            return InjectorResult(success: false,
                message: "Ruta del bundle no configurada.")
        }

        if let container = container {
            let bundleDir = container + "/" + basePath
            if ensureDirectoryTree(bundleDir) {
                NyxelActivityLog.record("BUNDLE DIR ok (mkdir): \(basePath)")
            } else {
                NyxelActivityLog.record("BUNDLE DIR mkdir fallo — fallback Foundation")
                let hRoot = DavizinGrantContainerAccess(container)
                try? FileManager.default.createDirectory(atPath: bundleDir, withIntermediateDirectories: true)
                DavizinReleaseContainerGrant(hRoot)
            }
            var isDir: ObjCBool = false
            let dirOk = FileManager.default.fileExists(atPath: bundleDir, isDirectory: &isDir) && isDir.boolValue
            NyxelActivityLog.record("BUNDLE DIR verify: \(dirOk ? "EXISTE" : "NO EXISTE") path=\(bundleDir.suffix(60))")
            if !dirOk {
                return InjectorResult(success: false,
                    message: "No se pudo crear el directorio de destino. El juego debe estar instalado.")
            }
        }

        guard !sessionToken.isEmpty else {
            NyxelActivityLog.record("BUNDLE ABORT: session token vacio — el usuario debe iniciar sesion de nuevo")
            return InjectorResult(success: false,
                message: "Sesion no establecida. Vuelve a iniciar sesion.")
        }

        NotificationCenter.default.post(name: .nyxelInjectionProgress,
            object: "Obteniendo lista de archivos...")

        guard let manifest = downloadBundleManifest(for: mode, key: key, hwid: hwid) else {
            return InjectorResult(success: false,
                message: "No se pudo obtener la lista de archivos. Revisa tu conexion.")
        }

        guard !manifest.files.isEmpty else {
            return InjectorResult(success: false,
                message: "No hay archivos configurados para este modo.")
        }

        let total = manifest.files.count
        let containerForWrite = container ?? "/not-available"
        var written = 0
        var failedCount = 0
        let lock = NSLock()
        let concurrencySem = DispatchSemaphore(value: 6)
        let group = DispatchGroup()
        let dlQueue = DispatchQueue(label: "com.davizin.bundle-dl", attributes: .concurrent)

        for fileName in manifest.files {
            guard isSafeBundleFileName(fileName) else {
                NyxelActivityLog.record("BUNDLE SKIP nombre rechazado: \(fileName.prefix(60))")
                lock.lock(); failedCount += 1; lock.unlock()
                continue
            }

            group.enter()
            concurrencySem.wait()
            dlQueue.async {
                defer { concurrencySem.signal(); group.leave() }

                guard let fileData = downloadBundleFile(
                    modeId: mode.id, fileName: fileName, key: key, hwid: hwid, session: sessionToken),
                      fileData.count > 0 else {
                    lock.lock(); failedCount += 1; lock.unlock()
                    return
                }

                let relPath = basePath + "/" + fileName
                let writeError = writeToContainer(
                    fileData, relPath: relPath,
                    container: containerForWrite, bundleID: bid)

                lock.lock()
                if let writeError = writeError {
                    NyxelActivityLog.record("BUNDLE WRITE FAIL \(fileName.prefix(40)): \(writeError.localizedDescription)")
                    failedCount += 1
                } else {
                    written += 1
                    let progress = written
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .nyxelInjectionProgress,
                            object: "Inyectando archivos... \(progress)/\(total)")
                    }
                }
                lock.unlock()
            }
        }

        group.wait()

        NyxelActivityLog.record("========== BUNDLE INJECTION TRACE END (written=\(written)/\(total) failed=\(failedCount)) ==========")

        if written == 0 {
            return InjectorResult(success: false,
                message: "No se pudo inyectar ningun archivo (\(failedCount)/\(total) fallaron). Revisa los logs de diagnostico.")
        }
        if failedCount == 0 {
            return InjectorResult(success: true,
                message: "\(mode.displayName) inyectado con exito! (\(written) archivos)")
        }
        return InjectorResult(success: true,
            message: "\(mode.displayName) inyectado parcialmente. \(written)/\(total) archivos escritos.")
    }

    private static func downloadBundleManifest(for mode: DavizinMode, key: String, hwid: String) -> BundleManifest? {
        guard !key.isEmpty else { return nil }
        guard let url = URL(string: "\(kCacheBaseURL)\(NyxelStringShield.pathBundle)\(mode.id)/manifest") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: NyxelStringShield.headerKey)
        request.setValue(hwid, forHTTPHeaderField: NyxelStringShield.headerHWID)
        KeyValidator.applySecurityHeaders(to: &request)
        request.timeoutInterval = 15

        let semaphore = DispatchSemaphore(value: 0)
        var result: BundleManifest?
        var diagStatus: Int = 0

        NyxelCertPinning.shared.session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error = error { NyxelActivityLog.record("BUNDLE MANIFEST \(mode.id): error=\(error.localizedDescription)"); return }
            let http = response as? HTTPURLResponse
            diagStatus = http?.statusCode ?? 0
            guard let http = http, http.statusCode == 200,
                  let data = data else { return }
            result = try? JSONDecoder().decode(BundleManifest.self, from: data)
            NyxelActivityLog.record("BUNDLE MANIFEST \(mode.id): status=\(diagStatus) files=\(result?.files.count ?? -1)")
        }.resume()

        _ = semaphore.wait(timeout: .now() + 17)
        if result == nil {
            NyxelActivityLog.record("BUNDLE MANIFEST \(mode.id): FALLO status=\(diagStatus)")
        }
        return result
    }

    private static func downloadBundleFile(modeId: String, fileName: String, key: String, hwid: String, session: String) -> Data? {
        guard !key.isEmpty else { NyxelActivityLog.record("BUNDLE DL \(fileName): key vacia"); return nil }
        guard !session.isEmpty else { NyxelActivityLog.record("BUNDLE DL \(fileName): sin session"); return nil }
        guard let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        guard let url = URL(string: "\(kCacheBaseURL)\(NyxelStringShield.pathBundle)\(modeId)/file/\(encoded)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: NyxelStringShield.headerKey)
        request.setValue(hwid, forHTTPHeaderField: NyxelStringShield.headerHWID)
        KeyValidator.applySecurityHeaders(to: &request)
        request.setValue(session, forHTTPHeaderField: NyxelStringShield.headerSession)
        request.timeoutInterval = 60

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        var diagStatus: Int = 0
        var diagBytes: Int = 0
        var diagError: String?

        NyxelCertPinning.shared.session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error = error { diagError = error.localizedDescription; return }
            let http = response as? HTTPURLResponse
            diagStatus = http?.statusCode ?? 0
            diagBytes = data?.count ?? 0
            guard let http = http, http.statusCode == 200,
                  let data = data, data.count > 28 else { return }
            if let plain = decrypt(data, session: session), plain.count > 0 {
                result = plain
            } else {
                diagError = "decrypt failed (enc=\(data.count) bytes)"
            }
        }.resume()

        let waitResult = semaphore.wait(timeout: .now() + 65)
        if waitResult == .timedOut {
            NyxelActivityLog.record("BUNDLE DL \(fileName): TIMEOUT 65s")
        } else if result == nil {
            NyxelActivityLog.record("BUNDLE DL \(fileName): FALLO status=\(diagStatus) bytes=\(diagBytes) err=\(diagError ?? "nil")")
        }
        return result
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
