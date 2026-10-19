import Foundation
import UIKit

// MARK: - Operation Guards
enum NyxelOperationGuard {
    /// Check before downloading/validating keys
    static func canProceedWithKeyValidation() -> Bool {
        guard NyxelSupportPolicy.isCurrentSystemSupported else {
            nyxelLog("🚫 Key validation blocked: \(NyxelSupportPolicy.currentSystemDescription) not supported", level: "WARN")
            return false
        }
        nyxelLog("✓ Key validation allowed for \(NyxelSupportPolicy.currentSystemDescription)", level: "INFO")
        return true
    }
    
    /// Check before injecting into Free Fire
    static func canProceedWithInjection() -> Bool {
        guard NyxelSupportPolicy.isCurrentSystemSupported else {
            nyxelLog("🚫 Injection blocked: \(NyxelSupportPolicy.currentSystemDescription) not supported", level: "WARN")
            return false
        }
        nyxelLog("✓ Injection allowed for \(NyxelSupportPolicy.currentSystemDescription)", level: "INFO")
        return true
    }
    
    /// Check before downloading/caching assets
    static func canProceedWithAssetDownload() -> Bool {
        guard NyxelSupportPolicy.isCurrentSystemSupported else {
            nyxelLog("🚫 Asset download blocked: \(NyxelSupportPolicy.currentSystemDescription) not supported", level: "WARN")
            return false
        }
        nyxelLog("✓ Asset download allowed for \(NyxelSupportPolicy.currentSystemDescription)", level: "INFO")
        return true
    }
}

// MARK: - Feature Availability
struct NyxelFeatureAvailability {
    static var supportsAssetBundles: Bool {
        NyxelSupportPolicy.isCurrentSystemSupported
    }
    
    static var supportsDirectInjection: Bool {
        let v = NyxelSupportPolicy.currentVersion
        // Direct injection available on iOS 17+
        return v.majorVersion >= 17
    }
    
    static var supportsBackgroundOperations: Bool {
        let v = NyxelSupportPolicy.currentVersion
        // Background operations available on iOS 16+
        return v.majorVersion >= 16
    }
    
    static var supportsEnhancedDiagnostics: Bool {
        let v = NyxelSupportPolicy.currentVersion
        // Enhanced diagnostics available on iOS 17+
        return v.majorVersion >= 17
    }
}

// MARK: - Compatibility State (SwiftUI compatible)
import Combine

@available(iOS 16.0, *)
class NyxelCompatibilityState: ObservableObject {
    @Published var isSupported: Bool = false
    @Published var systemDescription: String = ""
    @Published var deviceModel: String = ""
    @Published var deviceIdentifier: String = ""
    @Published var statusLabel: String = ""
    @Published var statusColor: UIColor = .red
    
    init() {
        checkCompatibility()
    }
    
    private func checkCompatibility() {
        DispatchQueue.main.async {
            self.isSupported = NyxelSupportPolicy.isCurrentSystemSupported
            self.systemDescription = NyxelSupportPolicy.currentSystemDescription
            self.deviceModel = NyxelSupportPolicy.currentDeviceModel
            self.deviceIdentifier = NyxelSupportPolicy.currentMachineIdentifier
            
            if self.isSupported {
                self.statusLabel = "Compatible ✓"
                self.statusColor = .systemGreen
            } else {
                self.statusLabel = "Incompatible ✗"
                self.statusColor = .systemRed
            }
        }
    }
}

// MARK: - URLSession Extension for Compatibility Checking
extension URLSession {
    func nyxelDataTask(
        with url: URL,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        guard NyxelOperationGuard.canProceedWithKeyValidation() else {
            let error = NSError(
                domain: "NyxelCompatibility",
                code: -999,
                userInfo: [NSLocalizedDescriptionKey: "Device not supported"]
            )
            completionHandler(nil, nil, error)
            return dataTask(with: url)
        }
        
        return dataTask(with: url, completionHandler: completionHandler)
    }
}

// MARK: - Notification Helper
extension NSNotification {
    static let nyxelCompatibilityChanged = NSNotification.Name("nyxel.compatibility.changed")
}

// MARK: - Pre-flight Checks
enum NyxelPreflightChecks {
    static func performAll() -> [CheckResult] {
        var results: [CheckResult] = []
        
        // iOS Version check
        let v = NyxelSupportPolicy.currentVersion
        let versionText = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        if NyxelSupportPolicy.isSupported(
            major: v.majorVersion,
            minor: v.minorVersion,
            patch: v.patchVersion,
            build: NyxelSupportPolicy.currentBuild
        ) {
            results.append(.init(name: "iOS Compatibility", passed: true, detail: "iOS \(versionText)"))
        } else {
            results.append(.init(name: "iOS Compatibility", passed: false, detail: "iOS \(versionText) not supported"))
        }
        
        // Device check
        results.append(.init(name: "Device Model", passed: true, detail: NyxelSupportPolicy.currentDeviceModel))
        
        // Home button check
        results.append(.init(name: "Face ID/Home Button", passed: true, detail: NyxelSupportPolicy.hasHomeButton ? "Home Button" : "Face ID"))
        
        // Build info check
        results.append(.init(name: "Build", passed: true, detail: NyxelSupportPolicy.currentBuild))
        
        // Asset support check
        results.append(.init(name: "Asset Bundles", passed: NyxelFeatureAvailability.supportsAssetBundles, detail: NyxelFeatureAvailability.supportsAssetBundles ? "Supported" : "Not supported"))
        
        // Injection support check
        results.append(.init(name: "Direct Injection", passed: NyxelFeatureAvailability.supportsDirectInjection, detail: NyxelFeatureAvailability.supportsDirectInjection ? "Supported" : "Not supported"))
        
        return results
    }
    
    struct CheckResult {
        let name: String
        let passed: Bool
        let detail: String
        
        var icon: String {
            passed ? "✓" : "✗"
        }
        
        var displayText: String {
            "\(icon) \(name): \(detail)"
        }
    }
}

// MARK: - App Lifecycle Hook
extension UIApplication {
    func logNyxelLaunchInfo() {
        nyxelLog("", level: "INFO") // Blank line
        nyxelLog("╔════════════════════════════════════════╗", level: "INFO")
        nyxelLog("║         NYXEL EXTERNAL LAUNCHED        ║", level: "INFO")
        nyxelLog("╚════════════════════════════════════════╝", level: "INFO")
        nyxelLog(NyxelSupportPolicy.getFullSystemInfo(), level: "INFO")
    }
}

// MARK: - Debugging Utilities
enum NyxelDebug {
    static var isDebuggingEnabled: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }
    
    static func dumpSystemInfo() -> String {
        var info = "═══ NYXEL DEBUG INFO ═══\n"
        info += "Version: \(NyxelSupportPolicy.currentSystemDescription)\n"
        info += "Device: \(NyxelSupportPolicy.currentDeviceModel)\n"
        info += "Identifier: \(NyxelSupportPolicy.currentMachineIdentifier)\n"
        info += "Build: \(NyxelSupportPolicy.currentBuild)\n"
        info += "Supported: \(NyxelSupportPolicy.isCurrentSystemSupported)\n"
        info += "Debugging: \(isDebuggingEnabled)\n"
        info += "════════════════════════\n"
        return info
    }
    
    static func printSystemInfo() {
        print(dumpSystemInfo())
    }
}
