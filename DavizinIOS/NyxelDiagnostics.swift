import Foundation
import UIKit

enum NyxelErrorCode {
    static let unsupportedSystem = "NYX-001"
    static let workerUnavailable = "NYX-002"
    static let invalidConfiguration = "NYX-003"
    static let gameUnavailable = "NYX-004"
    static let containerUnavailable = "NYX-005"
    static let operationCancelled = "NYX-006"
}

enum NyxelRemoteConfigStore {
    private static let savedAtKey = "nyxel.config.savedAt"
    private static let versionKey = "nyxel.config.version"
    private static let statusKey = "nyxel.config.status"

    static var savedAt: Date? {
        let value = UserDefaults.standard.double(forKey: savedAtKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }
    static var version: Int { UserDefaults.standard.integer(forKey: versionKey) }
    static var status: String { UserDefaults.standard.string(forKey: statusKey) ?? "Sin sincronizar" }
    static var ageDescription: String {
        guard let savedAt else { return "Nunca sincronizada" }
        let seconds = max(0, Int(Date().timeIntervalSince(savedAt)))
        if seconds < 60 { return "Hace unos segundos" }
        if seconds < 3600 { return "Hace \(seconds / 60) min" }
        if seconds < 86400 { return "Hace \(seconds / 3600) h" }
        return "Hace \(seconds / 86400) días"
    }
    static func recordAccepted(version: Int = 0) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: savedAtKey)
        UserDefaults.standard.set(version, forKey: versionKey)
        UserDefaults.standard.set("Configuración válida", forKey: statusKey)
    }
    static func recordFailure(_ message: String) { UserDefaults.standard.set(message, forKey: statusKey) }
}

/// Historial local breve; nunca almacena keys, tokens ni HWID.
enum NyxelActivityLog {
    private static let key = "nyxel.activity.log"
    private static let limit = 6

    static var entries: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func record(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let entry = "\(formatter.string(from: Date()))  \(message)"
        var values = entries
        values.insert(entry, at: 0)
        UserDefaults.standard.set(Array(values.prefix(limit)), forKey: key)
    }
}

/// Estado de disponibilidad de apps mediante los esquemas declarados en Info.plist.
enum NyxelInstalledGames {
    static func statusText() -> String {
        let maxInstalled = canOpen("freefiremax")
        let normalInstalled = canOpen("freefire") || canOpen("freefireth")
        let max = maxInstalled ? "✓ MAX instalado" : "— MAX no detectado"
        let normal = normalInstalled ? "✓ Free Fire instalado" : "— Free Fire no detectado"
        return "JUEGOS\n\(max)\n\(normal)"
    }

    private static func canOpen(_ scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
