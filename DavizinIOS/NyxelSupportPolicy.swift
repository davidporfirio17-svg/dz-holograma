import Foundation
import Darwin
import UIKit

// MARK: - Device Information Utilities
enum NyxelDeviceInfo {
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    
    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }
    
    static var doubleVersion: Double {
        let v = versionTuple
        return Double(v.major) + Double(v.minor) / 10.0
    }
    
    static var machineName: String {
        var s = utsname()
        uname(&s)
        return Mirror(reflecting: s.machine).children.reduce("") { id, e in
            guard let v = e.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
    }
    
    static var displayMachineName: String {
#if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machineName
#else
        return machineName
#endif
    }
    
    static var deviceModel: String {
        switch displayMachineName {
        // iPhone Pro models
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        // iPhone standard models
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone15,4": return "iPhone 14"
        case "iPhone15,5": return "iPhone 14 Plus"
        case "iPhone16,3": return "iPhone 15"
        case "iPhone16,4": return "iPhone 15 Plus"
        // Fallback
        default: return displayMachineName
        }
    }
    
    static var isHomeButton: Bool {
        let sel = NSSelectorFromString("_hasHomeButton")
        return UIDevice.responds(to: sel) && (UIDevice.perform(sel)?.takeUnretainedValue() as? Bool ?? false)
    }
    
    static var osBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }

        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            sysctlbyname("kern.osversion", pointer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return "" }
        return String(cString: buffer)
    }
    
    static var systemDescription: String {
        let version = versionTuple
        let versionText = "\(version.major).\(version.minor).\(version.patch)"
        let build = osBuild
        return build.isEmpty ? "iOS \(versionText)" : "iOS \(versionText) (\(build))"
    }
}

// MARK: - Nyxel Support Policy (Enhanced)
enum NyxelSupportPolicy {
    enum Status {
        case supported
        case unsupported

        var label: String { self == .supported ? "Compatible" : "No compatible" }
    }

    static let verifiedIOS17Range = "17.0–17.7.x"
    static let verifiedIOS18Range = "18.0–18.7.1"
    static let verifiedIOS26Range = "26.0–26.6.2"

    static let verifiedIOS27Builds: [(beta: Int, publicBeta: Int?, build: String)] = [
        (1, nil, "24A5355q"),
        (2, nil, "24A5370h"),
        (3, 1, "24A5380h"),
        (4, 2, "24A5390f")
    ]

    static var currentVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    /// Obtiene el build Darwin exacto, por ejemplo 24A5355q.
    static var currentBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }

        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            sysctlbyname("kern.osversion", pointer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return "" }
        return String(cString: buffer)
    }

    static func iOS27BetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.beta
    }

    static func iOS27PublicBetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.publicBeta
    }

    static func supportsVerifiedSystem(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }

        if major == 17 { return minor <= 7 }
        if major == 18 { return minor < 7 || (minor == 7 && patch <= 1) }
        if major == 26 { return minor < 6 || (minor == 6 && patch <= 2) }
        guard major == 27, minor == 0, patch == 0 else { return false }
        return iOS27BetaNumber(for: build) != nil
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        supportsVerifiedSystem(major: major, minor: minor, patch: patch, build: build)
    }

    static var status: Status { isCurrentSystemSupported ? .supported : .unsupported }

    static var isCurrentSystemSupported: Bool {
        let version = currentVersion
        return supportsVerifiedSystem(
            major: version.majorVersion,
            minor: version.minorVersion,
            patch: version.patchVersion,
            build: currentBuild
        )
    }

    static var currentSystemDescription: String {
        NyxelDeviceInfo.systemDescription
    }

    static var supportedRangesDescription: String {
        "iOS 17.0–17.7.x · iOS 18.0–18.7.1 · iOS 26.0–26.6.2 · iOS 27.0 builds verificados"
    }
    
    // MARK: - Device Information
    static var currentDeviceModel: String {
        NyxelDeviceInfo.deviceModel
    }
    
    static var currentMachineIdentifier: String {
        NyxelDeviceInfo.displayMachineName
    }
    
    static var hasHomeButton: Bool {
        NyxelDeviceInfo.isHomeButton
    }
    
    // MARK: - Diagnostic Information
    static func getFullSystemInfo() -> String {
        let v = currentVersion
        return """
        ═══ NYXEL SYSTEM INFO ═══
        Device: \(currentDeviceModel)
        Identifier: \(currentMachineIdentifier)
        iOS Version: \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)
        Build: \(currentBuild)
        Has Home Button: \(hasHomeButton)
        Compatibility Status: \(status.label)
        Supported Range: \(supportedRangesDescription)
        ════════════════════════
        """
    }
}

// MARK: - App Logger (for debugging & diagnostics)
class NyxelLogger {
    static let shared = NyxelLogger()
    
    @Published var logEntries: [String] = []
    private var logFile: URL? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsDirectory = paths.first else { return nil }
        return documentsDirectory.appendingPathComponent("nyxel_debug.log")
    }
    
    func log(_ message: String, level: String = "INFO") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formatted = "[\(timestamp)] [\(level)] \(message)"
        
        DispatchQueue.main.async {
            self.logEntries.append(formatted)
            if self.logEntries.count > 500 {
                self.logEntries.removeFirst(100)
            }
        }
        
        // Also write to file for persistence
        writeToFile(formatted)
    }
    
    func logInfo(_ message: String) { log(message, level: "INFO") }
    func logWarning(_ message: String) { log(message, level: "WARN") }
    func logError(_ message: String) { log(message, level: "ERROR") }
    func logSuccess(_ message: String) { log(message, level: "SUCCESS") }
    
    private func writeToFile(_ message: String) {
        guard let logFile = logFile else { return }
        let data = (message + "\n").data(using: .utf8) ?? Data()
        
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let fileHandle = FileHandle(forWritingAtPath: logFile.path) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logFile, options: .atomic)
        }
    }
    
    func getAllLogs() -> String {
        logEntries.joined(separator: "\n")
    }
    
    func clearLogs() {
        logEntries.removeAll()
        guard let logFile = logFile else { return }
        try? FileManager.default.removeItem(at: logFile)
    }
}

// MARK: - Global logging function
func nyxelLog(_ message: String, level: String = "INFO") {
    NyxelLogger.shared.log(message, level: level)
}
