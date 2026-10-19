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
        modelName(for: displayMachineName)
    }

    /// Traduce el identificador de hardware devuelto por `uname().machine` al nombre comercial.
    /// El identificador del bundle corresponde a la app, no al modelo del dispositivo.
    static func modelName(for hardwareIdentifier: String) -> String {
        switch hardwareIdentifier {
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPhone12,8": return "iPhone SE (2.ª generación)"

        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"

        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,6": return "iPhone SE (3.ª generación)"

        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"

        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"

        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,5": return "iPhone 16e"

        case "iPhone18,3": return "iPhone 17"
        case "iPhone18,1": return "iPhone 17 Pro"
        case "iPhone18,2": return "iPhone 17 Pro Max"
        case "iPhone18,4": return "iPhone Air"
        case "iPhone18,5": return "iPhone 17e"

        case "iPhone19,2": return "iPhone 18 Pro"
        case "iPhone19,3", "iPhone19,7": return "iPhone 18 Pro Max"
        case "iPhone19,4": return "iPhone Duo"

        case "iPad17,1", "iPad17,2": return "iPad Pro 11″ (M5)"
        case "iPad17,3", "iPad17,4": return "iPad Pro 13″ (M5)"
        case "iPad16,8", "iPad16,9": return "iPad Air 11″ (M4)"
        case "iPad16,10", "iPad16,11": return "iPad Air 13″ (M4)"
        case "iPad15,3", "iPad15,4": return "iPad Air 11″ (M3)"
        case "iPad15,5", "iPad15,6": return "iPad Air 13″ (M3)"
        case "iPad15,7", "iPad15,8": return "iPad (A16)"
        case "iPad16,1", "iPad16,2": return "iPad mini (A17 Pro)"
        case "iPad16,3", "iPad16,4": return "iPad Pro 11″ (M4)"
        case "iPad16,5", "iPad16,6": return "iPad Pro 13″ (M4)"
        case "iPad14,8", "iPad14,9": return "iPad Air 11″ (M2)"
        case "iPad14,10", "iPad14,11": return "iPad Air 13″ (M2)"
        case "iPad13,18", "iPad13,19": return "iPad (10.ª generación)"
        case "iPad14,3", "iPad14,4": return "iPad Pro 11″ (4.ª generación)"
        case "iPad14,5", "iPad14,6": return "iPad Pro 12,9″ (6.ª generación)"
        case "iPad13,16", "iPad13,17": return "iPad Air (5.ª generación)"
        case "iPad12,1", "iPad12,2": return "iPad (9.ª generación)"
        case "iPad14,1", "iPad14,2": return "iPad mini (6.ª generación)"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPad Pro 12,9″ (5.ª generación)"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPad Pro 11″ (3.ª generación)"
        case "iPad13,1", "iPad13,2": return "iPad Air (4.ª generación)"
        case "iPad11,6", "iPad11,7": return "iPad (8.ª generación)"
        case "iPad8,11", "iPad8,12": return "iPad Pro 12,9″ (4.ª generación)"
        case "iPad8,9", "iPad8,10": return "iPad Pro 11″ (2.ª generación)"
        case "iPad7,11", "iPad7,12": return "iPad (7.ª generación)"
        case "iPad11,3", "iPad11,4": return "iPad Air (3.ª generación)"
        case "iPad11,1", "iPad11,2": return "iPad mini (5.ª generación)"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": return "iPad Pro 12,9″ (3.ª generación)"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": return "iPad Pro 11″ (1.ª generación)"
        case "iPad7,5", "iPad7,6": return "iPad (6.ª generación)"
        case "iPad7,1", "iPad7,2": return "iPad Pro 12,9″ (2.ª generación)"
        case "iPad7,3", "iPad7,4": return "iPad Pro 10,5″"
        case "iPad6,11", "iPad6,12": return "iPad (5.ª generación)"
        case "iPad6,3", "iPad6,4": return "iPad Pro 9,7″"
        case "iPad6,7", "iPad6,8": return "iPad Pro 12,9″ (1.ª generación)"
        default:
            return hardwareIdentifier.hasPrefix("iPad") ? "iPad (\(hardwareIdentifier))" : hardwareIdentifier
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

    /// iOS 17–26 conserva la política amplia que ya utilizaba la aplicación.
    /// En iOS 27 se exige un build conocido porque el acceso directo al
    /// contenedor deja de ser una ruta fiable y debe usarse pairing + túnel.
    static func supportsVerifiedSystem(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        guard major >= 17 else { return false }
        guard major == 27 else { return major <= 26 }
        guard minor == 0 || minor == 2 else { return false }
        if minor == 0 && patch == 1 && build == "24A446" {
            return true
        }
        if minor == 2 {
            return ["24B5084k", "24B5089g"].contains(build)
        }
        return verifiedIOS27Builds.contains { $0.build == build }
            || ["24A435", "24A437"].contains(build)
    }

    /// Desde iOS 27, las operaciones sobre otro contenedor deben pasar por
    /// un registro de pairing y el túnel RSD/AirLift.
    static func requiresPairingTunnel(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        major >= 27
    }

    /// The bundled opa334 offset table is verified only through iOS 26.0.x.
    /// Newer systems must use the supported pairing/AirLift route instead.
    static func supportsKernelOffsets(major: Int, minor: Int) -> Bool {
        major >= 17 && (major < 26 || (major == 26 && minor == 0))
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
        "iOS 17–26 · iOS 27.0/27.2 (solo builds verificados) · iOS 27.0.1 (24A446)"
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
