import AVFoundation

/// Mantiene el proceso vivo en segundo plano mientras se publica el host de
/// emparejamiento: el usuario tiene que salir a Ajustes > Modo desarrollador
/// para ver "2424", y sin una sesión de audio activa iOS suspende la app en
/// segundos y mata el NWListener. Usa un buffer silencioso en bucle, igual
/// que External (declara UIBackgroundModes = audio). Solo vive mientras dura
/// el emparejamiento; no afecta nada fuera de la pestaña VPN.
enum NixelPairingKeepAlive {
    private static let player: AVAudioPlayer? = {
        let frameCount = 4410
        var samples = [Int16](repeating: 0, count: frameCount)
        samples[0] = 1 // evita que algunos route managers traten el buffer como "sin audio"
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let header = wavHeader(dataLength: data.count)
        return try? AVAudioPlayer(data: header + data)
    }()

    static func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        player?.numberOfLoops = -1
        player?.volume = 0.01
        player?.play()
    }

    static func stop() {
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func wavHeader(dataLength: Int, sampleRate: UInt32 = 44100) -> Data {
        var header = Data()
        func append(_ s: String) { header.append(s.data(using: .ascii)!) }
        func append(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        func append(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        append("RIFF"); append(UInt32(36 + dataLength)); append("WAVE")
        append("fmt "); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        append("data"); append(UInt32(dataLength))
        return header
    }
}
