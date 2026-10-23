import Foundation
import CommonCrypto

final class NyxelCertPinning: NSObject, URLSessionDelegate {
    static let shared = NyxelCertPinning()

    private static let pinnedDomains: Set<String> = {
        var d = Set<String>()
        d.insert(NyxelStringShield.workerHost)
        return d
    }()

    private static let pinnedSPKIHashes: Set<String> = [
        "MicrosoftRSARootCertificateAuthority2017",
        "DigiCertGlobalRootG2",
        "ABORHG+bKRGMrkPGEyLkfuFT7S2pC1SMK4x78khlEjM=",
        "JSMzqOOrtyOT1kmau6zKhgT676hGgczD5VMdRMyJZFA=",
        "RQeZkB42znUfsDIIFWIRiYEcKl7nHwNFwWCrnMMJbVc=",
    ]

    lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              Self.pinnedDomains.contains(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if verifyCertChain(serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func verifyCertChain(_ trust: SecTrust) -> Bool {
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else { return false }

        let certCount = SecTrustGetCertificateCount(trust)
        guard certCount > 0 else { return false }

        for i in 0..<certCount {
            guard let cert = secTrustCopyCert(trust, index: i) else { continue }
            let spkiHash = sha256SPKIHash(cert)
            if Self.pinnedSPKIHashes.contains(spkiHash) {
                return true
            }
        }

        return false
    }

    private func secTrustCopyCert(_ trust: SecTrust, index: Int) -> SecCertificate? {
        if #available(iOS 15.0, *) {
            guard let certs = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  index < certs.count else { return nil }
            return certs[index]
        } else {
            return SecTrustGetCertificateAtIndex(trust, index)
        }
    }

    private func sha256SPKIHash(_ cert: SecCertificate) -> String {
        let data = SecCertificateCopyData(cert) as Data
        guard let spki = extractSPKI(from: data) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        spki.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash).base64EncodedString()
    }

    private func extractSPKI(from derCert: Data) -> Data? {
        guard let key = SecCertificateCopyKey(SecCertificateCreateWithData(nil, derCert as CFData)!) else { return nil }
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else { return nil }
        return keyData
    }
}
