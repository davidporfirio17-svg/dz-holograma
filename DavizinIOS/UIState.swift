import Foundation
import UserNotifications

enum DavizinScreenStage: Equatable { case login, home, gameSelection, modeSelection, operation, profile }

enum DavizinGame: String, CaseIterable { case freeFire = "Free Fire", freeFireMax = "Free Fire MAX" }

struct DavizinMode: Hashable, Codable, Identifiable {
    let id: String
    let label: String
    let enabled: Bool
    let noticeTitle: String
    let noticeBody: String
    let noticeLevel: String
    let noticeEnabled: Bool
    let accessTier: String
    let pathMax: String?
    let pathNormal: String?
    let oneTime: Bool
    let consumed: Bool
    /// Visibilidad independiente por juego — antes "enabled" era global y
    /// afectaba ambos juegos a la vez.
    let enabledFreeFire: Bool
    let enabledFreeFireMax: Bool

    var rawValue: String { id }
    var displayName: String { label }

    func isEnabled(for game: DavizinGame) -> Bool {
        guard enabled else { return false }
        switch game {
        case .freeFire: return enabledFreeFire
        case .freeFireMax: return enabledFreeFireMax
        }
    }

    init(id: String, label: String, enabled: Bool, noticeTitle: String = "", noticeBody: String = "", noticeLevel: String = "yellow", noticeEnabled: Bool = true, accessTier: String = "basic", pathMax: String? = nil, pathNormal: String? = nil, oneTime: Bool = false, consumed: Bool = false, enabledFreeFire: Bool = true, enabledFreeFireMax: Bool = true) {
        self.id = id; self.label = label; self.enabled = enabled; self.noticeTitle = noticeTitle; self.noticeBody = noticeBody; self.noticeLevel = noticeLevel; self.noticeEnabled = noticeEnabled; self.accessTier = accessTier; self.pathMax = pathMax; self.pathNormal = pathNormal; self.oneTime = oneTime; self.consumed = consumed; self.enabledFreeFire = enabledFreeFire; self.enabledFreeFireMax = enabledFreeFireMax
    }

    private enum CodingKeys: String, CodingKey { case id, label, enabled, noticeTitle, noticeBody, noticeLevel, noticeEnabled, accessTier, pathMax, pathNormal, oneTime, consumed, enabledFreeFire = "enabledNormal", enabledFreeFireMax = "enabledMax" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        noticeTitle = try c.decodeIfPresent(String.self, forKey: .noticeTitle) ?? ""
        noticeBody = try c.decodeIfPresent(String.self, forKey: .noticeBody) ?? ""
        noticeLevel = try c.decodeIfPresent(String.self, forKey: .noticeLevel) ?? "yellow"
        noticeEnabled = try c.decodeIfPresent(Bool.self, forKey: .noticeEnabled) ?? true
        accessTier = try c.decodeIfPresent(String.self, forKey: .accessTier) ?? "basic"
        pathMax = try c.decodeIfPresent(String.self, forKey: .pathMax)
        pathNormal = try c.decodeIfPresent(String.self, forKey: .pathNormal)
        oneTime = try c.decodeIfPresent(Bool.self, forKey: .oneTime) ?? false
        consumed = try c.decodeIfPresent(Bool.self, forKey: .consumed) ?? false
        // Si el Worker todavia no manda estos 2 campos nuevos, por default
        // se comportan como el "enabled" global de antes (compatibilidad).
        enabledFreeFire = try c.decodeIfPresent(Bool.self, forKey: .enabledFreeFire) ?? enabled
        enabledFreeFireMax = try c.decodeIfPresent(Bool.self, forKey: .enabledFreeFireMax) ?? enabled
    }
}

enum DavizinModeCatalog {
    private static let storageKey = "dz_remote_mode_config_v4"
    static func all() -> [DavizinMode] {
        for key in [storageKey, "dz_remote_mode_config_v3", "dz_remote_mode_config_v2"] {
            guard let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([DavizinMode].self, from: data) else { continue }
            return saved.filter { isSafeID($0.id) && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return []
    }
    static func enabledModes() -> [DavizinMode] { all().filter(\.enabled) }
    /// Visibilidad real que ve el usuario en el mapa: filtra tambien por juego.
    static func enabledModes(for game: DavizinGame) -> [DavizinMode] { all().filter { $0.isEnabled(for: game) } }
    static func mode(id: String) -> DavizinMode? { all().first { $0.id == id } }
    static func save(_ modes: [DavizinMode]) {
        let clean = modes.filter { isSafeID($0.id) && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let data = try? JSONEncoder().encode(clean) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    static func markConsumed(_ id: String) {
        let updated = all().map { mode in
            guard mode.id == id else { return mode }
            return DavizinMode(id: mode.id, label: mode.label, enabled: false, noticeTitle: mode.noticeTitle, noticeBody: mode.noticeBody, noticeLevel: mode.noticeLevel, noticeEnabled: mode.noticeEnabled, accessTier: mode.accessTier, pathMax: mode.pathMax, pathNormal: mode.pathNormal, oneTime: mode.oneTime, consumed: true)
        }
        save(updated)
    }
    private static func isSafeID(_ id: String) -> Bool {
        guard id.count >= 1, id.count <= 32 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

enum DavizinOperationKind: String, CaseIterable { case runExploit = "Run Exploit", inject = "Inject" }
enum DavizinOperationState: Equatable {
    case idle, checking, running, injecting, succeeded(String), failed(String)
    var isBusy: Bool { switch self { case .checking, .running, .injecting: return true; case .idle, .succeeded, .failed: return false } }
}

enum NyxelCleanupStage: String { case idle }

enum NyxelCleanupFlow {
    static var stage: NyxelCleanupStage { .idle }
    static var game: DavizinGame? { nil }
    static var hasPendingWork: Bool { false }
    static func markInjectionWriteStarted(for game: DavizinGame) {}
    static func markInjectionSucceeded(for game: DavizinGame) {}
    static func markCleaningSucceeded(for game: DavizinGame) {}
    static func markGameOpened() {}
    static func markReturnedToNyxel() {}
    static func resetForFreshLaunch() {}
    static func requestReminderPermission(completion: @escaping (Bool) -> Void) { completion(false) }
    static func cancelReminder() {}
}

extension Notification.Name {
    static let nyxelInjectionProgress = Notification.Name("nyxelInjectionProgress")
}
