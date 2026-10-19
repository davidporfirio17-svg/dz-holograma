import UIKit
import UserNotifications

@_silgen_name("ALGetGrappaToken")
private func retainGrappaTokenSymbol(
    _ version: UInt32,
    _ deviceType: UInt32,
    _ protocolVersion: UInt32,
    _ output: UnsafeMutablePointer<UInt8>?,
    _ maximumLength: Int,
    _ outputLength: UnsafeMutablePointer<Int>?,
    _ errorBuffer: UnsafeMutablePointer<CChar>?,
    _ errorLength: Int
) -> Int32

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize Nyxel logging and system detection
        _ = retainGrappaTokenSymbol(0, 0, 0, nil, 0, nil, nil, 0)
        UNUserNotificationCenter.current().delegate = self
        clearLegacyInjectionNotifications()
        application.logNyxelLaunchInfo()
        return true
    }

    private func clearLegacyInjectionNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { Self.isLegacyInjectionNotification($0.content) }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .filter { Self.isLegacyInjectionNotification($0.request.content) }
                .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private static func isLegacyInjectionNotification(_ content: UNNotificationContent) -> Bool {
        let title = content.title.uppercased()
        return ["PASO", "SUCCESS", "FATAL", "NSERROR", "EXCEPTION"].contains { title.contains($0) }
    }

    /// Mostrar el recordatorio aunque Nyxel todavía esté en primer plano.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
