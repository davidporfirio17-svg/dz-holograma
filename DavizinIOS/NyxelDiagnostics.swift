import Foundation
import UIKit

extension Notification.Name {
    static let nyxelInjectionProgress = Notification.Name("nyxel.injection.progress")
}

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

/// Historial técnico local acotado; redacta posibles credenciales antes de guardarlas.
enum NyxelActivityLog {
    private static let key = "nyxel.activity.log"
    private static let limit = 1_600
    private static let lock = NSRecursiveLock()

    static var entries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return (UserDefaults.standard.stringArray(forKey: key) ?? []).map { sanitized($0) }
    }

    static var recentEntries: [String] { Array(entries.prefix(100)) }

    static func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let entry = "\(formatter.string(from: Date()))  \(sanitized(message))"
        var values = UserDefaults.standard.stringArray(forKey: key) ?? []
        values.insert(entry, at: 0)
        UserDefaults.standard.set(Array(values.prefix(limit)), forKey: key)
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func sanitized(_ value: String) -> String {
        let patterns = [
            #"(?i)(["']?(?:authorization|api[_ -]?key|session[_ -]?key|access[_ -]?token|refresh[_ -]?token|password|secret|hwid|token|grappa[_ -]?(?:key|secret|token)|pairing[_ -]?(?:key|secret|token))["']?)\s*[:=]\s*("[^"]*"|'[^']*'|[^,;\s}\]]+)"#
        ]
        let redacted = patterns.reduce(value) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "$1=[REDACTED]", options: .regularExpression)
        }
        let pinRedacted = redacted.replacingOccurrences(
            of: #"(?i)(PIN\s+recibido\s+por\s+AirLift:\s*)\d{4,8}\b"#,
            with: "$1[REDACTED]",
            options: .regularExpression
        )
        let containersRedacted = pinRedacted.replacingOccurrences(
            of: #"(?i)(/var/mobile/Containers/Data/Application/)[A-F0-9-]{20,}"#,
            with: "$1[APP_CONTAINER]",
            options: .regularExpression
        )
        return containersRedacted.replacingOccurrences(
            of: #"(?i)(/private)?/var/mobile/Containers/Data/Application/[^\s,;]+/tmp/nyxel-airlift-[^\s,;]+"#,
            with: "[AIRLIFT_TEMP_PATH]",
            options: .regularExpression
        )
    }
}

enum NyxelInstalledGames {
    static func isInstalled(for game: DavizinGame) -> Bool {
        switch game {
        case .freeFireMax:
            return canOpen("freefiremax")
        case .freeFire:
            return canOpen("freefire") || canOpen("freefireth")
        }
    }

    private static func canOpen(_ scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
