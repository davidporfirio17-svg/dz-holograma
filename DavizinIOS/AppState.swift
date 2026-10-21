import SwiftUI
import Combine

class AppState: ObservableObject {
    
    @Published var isAuthenticated: Bool = false
    @Published var currentKey: String = ""
    @Published var isInjected: Bool = false
    @Published var statusMessage: String = "Listo"
    @Published var isWorking: Bool = false
    
    // COUNTDOWN
    @Published var expirationTime: Int64 = 0
    @Published var remainingDays: Int = 0
    @Published var remainingHours: Int = 0
    @Published var remainingMinutes: Int = 0
    @Published var remainingSeconds: Int = 0
    @Published var isExpired: Bool = false
    
    let appVersion: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.4"
    let freeFireBundleID = "com.dts.freefiremax"
    let freeFireName = "Free Fire MAX"
    
    private var countdownTimer: Timer?
    
    init() {
        // NO cargar key automáticamente - SIEMPRE pedir
        isAuthenticated = false
        currentKey = ""
        checkInjectionStatus()
    }
    
    func checkInjectionStatus() {
        isInjected = InjectorService.checkIsInjected(bundleID: freeFireBundleID)
    }
    
    func saveKey(_ key: String, expirationMs: Int64) {
        currentKey = key
        expirationTime = expirationMs
        // NO guardar en UserDefaults - se pide siempre
        isAuthenticated = true
        startCountdown()
    }
    
    func logout() {
        isAuthenticated = false
        currentKey = ""
        expirationTime = 0
        remainingDays = 0
        remainingHours = 0
        remainingMinutes = 0
        remainingSeconds = 0
        isExpired = false
        stopCountdown()
        // NO limpiar UserDefaults - se pide fresh key siempre
    }
    
    func startCountdown() {
        stopCountdown()
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
    }
    
    func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    private func updateCountdown() {
        let now = Date().timeIntervalSince1970 * 1000
        let remaining = expirationTime - Int64(now)
        
        if remaining <= 0 {
            isExpired = true
            remainingDays = 0
            remainingHours = 0
            remainingMinutes = 0
            remainingSeconds = 0
            stopCountdown()
            return
        }
        
        isExpired = false
        let totalSeconds = remaining / 1000
        remainingDays = Int(totalSeconds / 86400)
        remainingHours = Int((totalSeconds % 86400) / 3600)
        remainingMinutes = Int((totalSeconds % 3600) / 60)
        remainingSeconds = Int(totalSeconds % 60)
    }
    
    func expirationDate() -> Date {
        return Date(timeIntervalSince1970: Double(expirationTime) / 1000)
    }
    
    deinit {
        stopCountdown()
    }
}
