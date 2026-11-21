import UIKit
import CommonCrypto

final class TamperGuard {
    static let shared = TamperGuard()

    private var result: Bool?

    func verify() -> Bool {
        if let r = result { return r }
        let ok = performChecks()
        result = ok
        if !ok { showAlert() }
        return ok
    }

    private func performChecks() -> Bool {
        guard Bundle.main.bundleIdentifier == "com.apple.mobile.MobileHouseArrest" else { return false }

        guard let exec = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              exec == "DavizinIOS" else { return false }

        guard let token = Bundle.main.object(forInfoDictionaryKey: "_sys") as? String,
              token.count == 16 else { return false }

        guard let assetsURL = Bundle.main.url(forResource: "Assets", withExtension: "car"),
              let data = try? Data(contentsOf: assetsURL) else { return false }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return hash == token
    }

    private func showAlert() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first,
                  let vc = window.rootViewController else { return }
            let alert = UIAlertController(
                title: "Modificaci\u{00f3}n detectada",
                message: "Esta aplicaci\u{00f3}n ha sido modificada y no funcionar\u{00e1}.",
                preferredStyle: .alert
            )
            vc.present(alert, animated: true)
        }
    }
}
