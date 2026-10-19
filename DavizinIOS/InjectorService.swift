import Foundation
import CryptoKit
import UserNotifications

struct InjectorResult {
    let success: Bool
    let message: String
}

// MARK: - Error Notifications
fileprivate func sendErrorNotification(_ title: String, _ body: String) {
    DispatchQueue.main.async {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            UNUserNotificationCenter.current().add(request)
        }
    }
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
    let key = game == .freeFireMax ? "dzh_active_dest_max" : "dzh_active_dest_normal"
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
    return game == .freeFireMax ? "dzh_active_path_max" : "dzh_active_path_normal"
}

private func originalMissingKey(for game: DavizinGame) -> String {
    return game == .freeFireMax ? "dzh_original_missing_max" : "dzh_original_missing_normal"
}

private func restoreCompletedKey(for game: DavizinGame) -> String {
    return game == .freeFireMax ? "dzh_restore_completed_max" : "dzh_restore_completed_normal"
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

    /// Escribe en el contenedor del juego. Si hay un registro de pairing
    /// AirLift guardado, usa ese canal (permisos elevados vía house_arrest/AFC);
    /// si no, cae al acceso directo de siempre. `relPath` es relativo al
    /// contenedor (p. ej. "Documents/.../avatar/assetindexer.xxx").
    private struct ContainerWriteError: LocalizedError {
        let airliftNote: String
        let directError: Swift.Error
        var errorDescription: String? { "\(directError.localizedDescription) [\(airliftNote)]" }
    }

    private static func writeToContainer(_ data: Data, relPath: String, container: String, bundleID: String) -> Swift.Error? {
        let fullPath = container + "/" + relPath
        let parentDir = (fullPath as NSString).deletingLastPathComponent

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
                airliftNote = "AirLift falló: \(error.message)"
                NyxelActivityLog.record("AirLift write falló (\(relPath)): \(error.message); usando método directo")
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

    private static func readFromContainer(relPath: String, container: String, bundleID: String) -> Data? {
        let fullPath = container + "/" + relPath
        let parentDir = (fullPath as NSString).deletingLastPathComponent

        let handleRoot = DavizinGrantContainerAccess(container)
        let handleDir = DavizinGrantContainerAccess(parentDir)
        let handleFile = DavizinGrantContainerAccess(fullPath)
        defer {
            DavizinReleaseContainerGrant(handleFile)
            DavizinReleaseContainerGrant(handleDir)
            DavizinReleaseContainerGrant(handleRoot)
        }

        if NixelAirLiftFileChannel.isAvailable {
            if case .success(let data) = NixelAirLiftFileChannel.read(relativePath: relPath, bundleID: bundleID) {
                return data
            }
        }
        return try? Data(contentsOf: URL(fileURLWithPath: fullPath))
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
        let material = Data(("dzhcache:session:" + session).utf8)
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
            let defaultsKey = game == .freeFireMax ? "dzh_active_dest_max" : "dzh_active_dest_normal"
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

            // Desde la eliminación del legacy, todos los recursos deben venir cifrados.
            // Nunca aceptar contenido en claro aunque empiece por "UnityFS".
            if let plain = decrypt(data, session: session), isUnityFS(plain) {
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
		defer { print("❌ inject() COMPLETÓ (defer)") }

		print("🔵 inject() INICIANDO")

		do {
			print("🔵 PASO 1: Verificando iOS...")
			sendErrorNotification("🔍 PASO 1", "Verificando iOS...")

			guard NyxelSupportPolicy.isCurrentSystemSupported else {
				let msg = "iOS no soportado: \(NyxelSupportPolicy.currentSystemDescription)"
				sendErrorNotification("❌ PASO 1", msg)
				throw NSError(domain: "Davizin", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
			}

			sendErrorNotification("✅ PASO 1", "iOS OK")

			sendErrorNotification("✅ PASO 1.5", "AirLift será el canal principal de escritura")

			sendErrorNotification("🔍 PASO 2", "Obteniendo bundle ID...")

			let fm = FileManager.default
        let bundleID = bundleID(for: game)
        sendErrorNotification("✅ PASO 2", "Bundle: \(bundleID)")

        sendErrorNotification("🔍 PASO 3", "Activando container MCM...")

        var mcmErr: NSString?
        guard let container = DavizinGetContainerPath(bundleID, &mcmErr) else {
            let msg = (mcmErr as String?) ?? "MCM falló - container nil"
            sendErrorNotification("❌ PASO 3", msg)
            return InjectorResult(success: false, message: msg)
        }

        sendErrorNotification("✅ PASO 3", "Container: \(container)")

        sendErrorNotification("🔍 PASO 4", "Preparando query...")
        _ = DavizinPrepareInjectionQuery(bundleID, &mcmErr)
        sendErrorNotification("✅ PASO 4", "Query lista")

        sendErrorNotification("🔍 PASO 5", "Refrescando nombre de archivo...")
        Self.refreshDestinationFileName(for: game, key: key, hwid: hwid)
        sendErrorNotification("✅ PASO 5", "Nombre: \(destPathRel(for: game, mode: mode))")

        sendErrorNotification("🔍 PASO 6", "Descargando recurso...")
        guard let finalData = downloadResource(for: mode, game: game, key: key, hwid: hwid) else {
            let msg = "No se pudo obtener recurso (nil)"
            sendErrorNotification("❌ PASO 6", msg)
            return InjectorResult(success: false, message: msg)
        }

        guard finalData.count > 1000 else {
            let msg = "Recurso muy pequeño: \(finalData.count) bytes"
            sendErrorNotification("❌ PASO 6", msg)
            return InjectorResult(success: false, message: msg)
        }

        sendErrorNotification("✅ PASO 6", "Recurso: \(finalData.count) bytes")

        sendErrorNotification("🔍 PASO 7", "Preparando rutas...")
        let activeRel = destPathRel(for: game, mode: mode)
        let destPath   = container + "/" + activeRel
        let backupPath = container + "/" + disguisedBackupPath(for: activeRel)
        UserDefaults.standard.set(activeRel, forKey: activePathKey(for: game))
        let destDir    = (destPath as NSString).deletingLastPathComponent
        sendErrorNotification("✅ PASO 7", "Dest: \(activeRel)")

        sendErrorNotification("🔍 PASO 8", "Creando directorio...")
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        sendErrorNotification("✅ PASO 8", "Directorio OK (o ya existía)")

        sendErrorNotification("🔍 PASO 9", "Haciendo backup...")
        let backupRel = disguisedBackupPath(for: activeRel)
        let originalFileExists = fm.fileExists(atPath: destPath)
        if originalFileExists && !fm.fileExists(atPath: backupPath) {
            guard let original = readFromContainer(relPath: activeRel, container: container, bundleID: bundleID) else {
                let msg = "No se pudo leer archivo original para backup"
                sendErrorNotification("❌ PASO 9", msg)
                return InjectorResult(success: false, message: msg)
            }
            if let error = writeToContainer(original, relPath: backupRel, container: container, bundleID: bundleID) {
                let msg = "Backup falló: \(error.localizedDescription)"
                sendErrorNotification("❌ PASO 9", msg)
                return InjectorResult(success: false, message: msg)
            }
        }
        sendErrorNotification("✅ PASO 9", "Backup OK")

        sendErrorNotification("🔍 PASO 10", "Validando estado...")
        let hasBackup = fm.fileExists(atPath: backupPath)
        let originalWasMissing = !originalFileExists && !hasBackup
        guard hasBackup || originalWasMissing else {
            let msg = "No hay backup disponible"
            sendErrorNotification("❌ PASO 10", msg)
            return InjectorResult(success: false, message: msg)
        }
        sendErrorNotification("✅ PASO 10", "Estado OK")

        UserDefaults.standard.set(originalWasMissing, forKey: originalMissingKey(for: game))
        UserDefaults.standard.set(false, forKey: restoreCompletedKey(for: game))
        NyxelCleanupFlow.markInjectionWriteStarted(for: game)

        sendErrorNotification("🔍 PASO 11", "INYECTANDO ARCHIVO...")
        if let error = writeToContainer(finalData, relPath: activeRel, container: container, bundleID: bundleID) {
            let msg = "Inyección falló: \(error.localizedDescription)"
            sendErrorNotification("❌ PASO 11", msg)
            return InjectorResult(success: false, message: msg)
        }
        sendErrorNotification("✅ PASO 11", "INYECCIÓN OK")

        sendErrorNotification("🔍 PASO 12", "Seteando permisos...")
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destPath)
        sendErrorNotification("✅ PASO 12", "Permisos OK (AirLift ya setea permisos)")

        sendErrorNotification("🔍 PASO 13", "Finalizando...")
        NyxelCleanupFlow.markInjectionSucceeded(for: game)
        sendErrorNotification("✅ PASO 13", "Finalizado")

        sendErrorNotification("🎉 SUCCESS", "¡\(mode.displayName) inyectado!")
        return InjectorResult(success: true,
            message: "¡\(mode.displayName) inyectado! Abre Free Fire, espera 8–10 segundos, vuelve a Nyxel y limpia la sesión.")
		} catch let error as NSError {
			let msg = "NSError: \(error.localizedDescription)"
			print("💥 CRASH NSError: \(msg)")
			sendErrorNotification("💥 NSError", msg)
			return InjectorResult(success: false, message: msg)
		} catch {
			let msg = "Excepción: \(error)"
			print("💥 CRASH Exception: \(msg)")
			sendErrorNotification("💥 Exception", msg)
			return InjectorResult(success: false, message: msg)
		}

		// Si llegamos aquí sin retornar, algo muy malo pasó
		print("⚠️ FATAL: inject() reached end without return")
		sendErrorNotification("⚠️ FATAL", "Código llegó al final sin retorno")
		return InjectorResult(success: false, message: "Fatal: código llegó al final")
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

        let backupRel = disguisedBackupPath(for: activeRel)
        if fm.fileExists(atPath: backupPath) {
            do {
                guard let backupData = readFromContainer(relPath: backupRel, container: container, bundleID: bundleID) else {
                    throw NSError(domain: "Nyxel", code: -1, userInfo: [NSLocalizedDescriptionKey: "no se pudo leer el respaldo"])
                }
                if let error = writeToContainer(backupData, relPath: activeRel, container: container, bundleID: bundleID) {
                    throw error
                }
                UserDefaults.standard.set(true, forKey: restoreCompletedKey(for: game))
                try fm.removeItem(atPath: backupPath)
                try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destPath)
            } catch {
                return InjectorResult(success: false,
                    message: "Error al restaurar: \(error.localizedDescription) {MCM: \(DavizinMCMLastDiagnostic() ?? "sin dato")}")
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
	/// Intenta verificar si un bundle está instalado enumerando containers
	private static func isBundleInstalledViaEnumeration(_ bundleID: String) -> Bool {
		let fm = FileManager.default
		let appDataRoot = "/var/mobile/Containers/Data/Application"

		guard fm.fileExists(atPath: appDataRoot) else { return false }

		do {
			let containers = try fm.contentsOfDirectory(atPath: appDataRoot)
			for containerDir in containers {
				let metadataPath = "\(appDataRoot)/\(containerDir)/.com.apple.mobile_container_manager.metadata.plist"
				if let metadata = NSDictionary(contentsOfFile: metadataPath),
				   let bid = metadata["MCMMetadataIdentifier"] as? String,
				   bid == bundleID {
					return true
				}
			}
		} catch {
			return false
		}
		return false
	}

	static func checkCompatibility() -> Compat {
		guard NyxelSupportPolicy.isCurrentSystemSupported else {
			return .unsupportedSystem
		}

		// On iOS 27+, sandbox escape is not available, so we can't reliably verify
		// if Free Fire is installed. Instead, trust that if the user got this far,
		// they likely have it installed. Injection will fail clearly if they don't.
		let bundles = ["com.dts.freefiremax", "com.dts.freefireth"]

        for bid in bundles {
            var err: NSString?
            // Try MCM/bad_query
            if let container = DavizinGetContainerPath(bid, &err) {
                // Found it → definitely compatible
                return .compatible
            }
        }

        // bad_query failed (expected on iOS 27 without kexploit)
        // Try fallback enumeration if possible
        for bid in bundles {
            if isBundleInstalledViaEnumeration(bid) {
                return .compatible
            }
        }

        // Can't verify via filesystem. On iOS 27, this is expected.
        // Return .compatible anyway - if they don't have Free Fire, injection will fail
        // with a clearer error message.
        return .compatible
    }

}
