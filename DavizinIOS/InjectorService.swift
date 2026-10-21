import Foundation
import CryptoKit

struct InjectorResult {
    let success: Bool
    let message: String
}

// Carpeta base donde vive el archivo dentro del contenedor de Free Fire.
private let kBaseFolder = "Documents/contentcache/Compulsory/ios/gameassetbundles/avatar"
private let kConfigURL = "https://dz-holograma.davidporfirio17.workers.dev/app-config"

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

/// Nombre de respaldo disfrazado: antes era "<archivo>.original", que se ve
/// obvio en Filza/cualquier explorador de archivos (delata que algo se tocó).
/// Ahora se genera un nombre determinista con el mismo patron visual que un
/// asset real de Unity ("assetindexer.<hash>"), sin extension rara, y vive
/// en la misma carpeta — se mezcla con los demas archivos de assets reales.
private func disguisedBackupPath(for relPath: String) -> String {
    let folder = (relPath as NSString).deletingLastPathComponent
    let digest = SHA256.hash(data: Data(relPath.utf8))
    let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
    let disguisedName = "assetindexer." + String(hex.prefix(28))
    return folder.isEmpty ? disguisedName : folder + "/" + disguisedName
}

// Base del Worker que sirve los cache_res desde KV.
private let kCacheBaseURL = "https://dz-holograma.davidporfirio17.workers.dev"

class InjectorService {

    /// Bundle ID del contenedor segun el juego.
    private static func bundleID(for game: DavizinGame) -> String {
        switch game {
        case .freeFireMax: return "com.dts.freefiremax"
        case .freeFire:    return "com.dts.freefireth"
        }
    }

    /// Comprueba si el bundle está instalado y accesible en el sistema verificado.
    /// Esta función solo informa el estado; no modifica archivos ni intenta inyectar.
    static func isBundleAvailable(for game: DavizinGame) -> Bool {
        guard NyxelSupportPolicy.isCurrentSystemSupported else { return false }
        var error: NSString?
        guard let container = DavizinGetContainerPath(bundleID(for: game), &error) else { return false }
        return FileManager.default.fileExists(atPath: container)
    }

    /// Ruta del Worker para cada modo y juego (descarga desde KV).
    /// Free Fire MAX usa slots base; Free Fire normal usa el sufijo _ff.
    private static func remoteSlot(for mode: DavizinMode, game: DavizinGame) -> String {
        return game == .freeFire ? mode.id + "_ff" : mode.id
    }

    /// Deriva una clave AES-256 temporal desde la sesión efímera del Worker.
    /// No existe una clave de recursos permanente dentro de la IPA.
    private static func cacheKey(session: String) -> SymmetricKey {
        let material = Data(("dzcache:session:" + session).utf8)
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }

    /// Un cache_res valido siempre empieza con la firma ASCII "UnityFS".
    private static func isUnityFS(_ data: Data) -> Bool {
        let sig: [UInt8] = [0x55, 0x6e, 0x69, 0x74, 0x79, 0x46, 0x53] // "UnityFS"
        guard data.count >= sig.count else { return false }
        return Array(data.prefix(sig.count)) == sig
    }

    /// Descifra un blob AES-GCM con formato [12 bytes IV][ciphertext+tag].
    /// Devuelve nil si el blob no es válido o la clave no corresponde.
    private static func decrypt(_ blob: Data, session: String) -> Data? {
        guard blob.count > 12 + 16 else { return nil }
        // Normalizar a un Data con indices desde 0 (una respuesta de red puede no estarlo,
        // y CryptoKit falla silenciosamente si los indices no arrancan en 0).
        let clean = Data(blob)
        // Separar manualmente: [nonce 12][ciphertext ...][tag 16]
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

    /// Actualiza opcionalmente el nombre de destino. Si falla, conserva el respaldo local.
    private static func refreshDestinationFileName(for game: DavizinGame, key: String, hwid: String) {
        guard let url = URL(string: kConfigURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-DZ-Key")
        request.setValue(hwid, forHTTPHeaderField: "X-DZ-HWID")
        KeyValidator.applySecurityHeaders(to: &request)
        request.timeoutInterval = 8
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
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

    /// Descarga el cache_res del modo desde el Worker. Devuelve el contenido YA DESCIFRADO.
    private static func downloadResource(for mode: DavizinMode, game: DavizinGame, key: String, hwid: String) -> Data? {
        guard !key.isEmpty else { return nil }
        guard let session = KeyValidator.currentSessionToken, !session.isEmpty else { return nil }
        guard let url = URL(string: "\(kCacheBaseURL)/avatar/\(remoteSlot(for: mode, game: game))") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-DZ-Key")
        request.setValue(hwid, forHTTPHeaderField: "X-DZ-HWID")
        KeyValidator.applySecurityHeaders(to: &request)
        request.timeoutInterval = 20

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
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

	static func inject(game: DavizinGame, mode: DavizinMode, key: String, hwid: String) -> InjectorResult {
		guard NyxelSupportPolicy.isCurrentSystemSupported else {
			return InjectorResult(
				success: false,
				message: "Versión no verificada: \(NyxelSupportPolicy.currentSystemDescription)"
			)
		}

		let fm = FileManager.default
        let bundleID = bundleID(for: game)

        var mcmErr: NSString?
        guard let container = DavizinGetContainerPath(bundleID, &mcmErr) else {
            return InjectorResult(success: false,
                message: (mcmErr as String?) ?? "Container no encontrado")
        }

        // La configuración es opcional; ante error se usan los valores originales.
        Self.refreshDestinationFileName(for: game, key: key, hwid: hwid)

        // Descargar + descifrar el cache_res del modo (unica fuente).
        guard let finalData = downloadResource(for: mode, game: game, key: key, hwid: hwid),
              finalData.count > 1000 else {
            return InjectorResult(success: false,
                message: "No se pudo obtener el recurso. Revisa tu conexión e inténtalo de nuevo.")
        }

        let activeRel = destPathRel(for: game, mode: mode)
        let destPath   = container + "/" + activeRel
        let backupPath = container + "/" + disguisedBackupPath(for: activeRel)
        UserDefaults.standard.set(activeRel, forKey: activePathKey(for: game))
        let destDir    = (destPath as NSString).deletingLastPathComponent

        try? fm.createDirectory(atPath: destDir,
                                withIntermediateDirectories: true)

        let originalFileExists = fm.fileExists(atPath: destPath)
        if originalFileExists && !fm.fileExists(atPath: backupPath) {
            do {
                let original = try Data(contentsOf: URL(fileURLWithPath: destPath))
                try original.write(to: URL(fileURLWithPath: backupPath))
            } catch {
                return InjectorResult(success: false,
                    message: "Error haciendo backup: \(error.localizedDescription)")
            }
        }

        let hasBackup = fm.fileExists(atPath: backupPath)
        let originalWasMissing = !originalFileExists && !hasBackup
        guard hasBackup || originalWasMissing else {
            return InjectorResult(success: false,
                message: "No se encontró un archivo original restaurable. No se inyectó nada.")
        }

        UserDefaults.standard.set(originalWasMissing, forKey: originalMissingKey(for: game))
        UserDefaults.standard.set(false, forKey: restoreCompletedKey(for: game))
        NyxelCleanupFlow.markInjectionWriteStarted(for: game)

        do {
            try finalData.write(to: URL(fileURLWithPath: destPath), options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destPath)
        } catch {
                return InjectorResult(success: false,
                    message: "Error al inyectar: \(error.localizedDescription)")
        }

        NyxelCleanupFlow.markInjectionSucceeded(for: game)

        return InjectorResult(success: true,
            message: "¡\(mode.displayName) inyectado! Abre Free Fire, espera 8–10 segundos, vuelve a Nyxel y limpia la sesión.")
    }

    static func uninject(game: DavizinGame) -> InjectorResult {
        let fm = FileManager.default
        let bundleID = bundleID(for: game)

        var mcmErr: NSString?
        guard let container = DavizinGetContainerPath(bundleID, &mcmErr) else {
            return InjectorResult(success: false,
                message: (mcmErr as String?) ?? "Container no encontrado")
        }

        let activeRel = UserDefaults.standard.string(forKey: activePathKey(for: game)).flatMap { isSafeRelativePath($0) ? $0 : nil } ?? legacyDestPathRel(for: game)
        let destPath   = container + "/" + activeRel
        let backupPath = container + "/" + disguisedBackupPath(for: activeRel)

        if fm.fileExists(atPath: backupPath) {
            do {
                let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
                try backupData.write(to: URL(fileURLWithPath: destPath), options: .atomic)
                UserDefaults.standard.set(true, forKey: restoreCompletedKey(for: game))
                try fm.removeItem(atPath: backupPath)
                try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destPath)
            } catch {
                return InjectorResult(success: false,
                    message: "Error al restaurar: \(error.localizedDescription)")
            }
        } else if UserDefaults.standard.bool(forKey: originalMissingKey(for: game)) {
            do {
                if fm.fileExists(atPath: destPath) { try fm.removeItem(atPath: destPath) }
                UserDefaults.standard.set(true, forKey: restoreCompletedKey(for: game))
            } catch {
                return InjectorResult(success: false,
                    message: "Error al retirar el archivo temporal: \(error.localizedDescription)")
            }
        } else if UserDefaults.standard.bool(forKey: restoreCompletedKey(for: game)) {
            // El original ya quedó escrito; se conserva la confirmación tras un cierre inesperado.
        } else {
            return InjectorResult(success: false,
                message: "No hay un respaldo restaurable; no se confirmó la limpieza.")
        }

        UserDefaults.standard.set(false, forKey: originalMissingKey(for: game))

        return InjectorResult(success: true,
            message: "Sesión limpia. Pulsa Abrir juego para volver a Free Fire.")
    }

    /// Resultado del chequeo de compatibilidad del dispositivo.
	enum Compat {
		case compatible          // puede acceder al contenedor -> puede inyectar
		case noGameInstalled     // Free Fire no esta instalado
		case notCompatible       // el juego esta pero no se puede acceder (iOS no compatible)
		case unsupportedSystem   // la versión/build del sistema no está verificada
    }

	/// Prueba REAL si el dispositivo puede inyectar, intentando acceder al
	/// contenedor de Free Fire (MAX o normal) via MCM. No inyecta nada.
	static func checkCompatibility() -> Compat {
		guard NyxelSupportPolicy.isCurrentSystemSupported else {
			return .unsupportedSystem
		}

		let fm = FileManager.default
        let bundles = ["com.dts.freefiremax", "com.dts.freefireth"]

        var algunInstalado = false
        for bid in bundles {
            var err: NSString?
            if let container = DavizinGetContainerPath(bid, &err) {
                // Conseguimos el contenedor: probamos que exista y sea accesible
                if fm.fileExists(atPath: container) {
                    return .compatible
                }
                algunInstalado = true
            }
        }
        // Si obtuvimos algun path pero no accesible -> instalado pero no compatible
        // Si nunca obtuvimos path -> el juego no esta instalado
        return algunInstalado ? .notCompatible : .noGameInstalled
    }

}
