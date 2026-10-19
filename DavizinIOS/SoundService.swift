import AVFoundation
import AudioToolbox
import UIKit

// MARK: - SoundService — tonos generados por codigo, sin archivos de audio externos.
// Equivalente nativo de la logica Web Audio API del prototipo HTML:
// playClick (tap corto), playChime (confirmacion), y el tono ascendente del hold-to-confirm.

final class SoundService {
    static let shared = SoundService()

    /// Controlado desde Ajustes. Si es false, ningun sonido se reproduce.
    var isEnabled: Bool = true

    /// Preferencia independiente para la voz "Opción activada".
    private let activationVoiceKey = "nyxel.activation.voice.enabled"
    var activationVoiceEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: activationVoiceKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: activationVoiceKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: activationVoiceKey) }
    }

    private let engine = AVAudioEngine()
    private let mixer: AVAudioMixerNode
    private var activationPlayer: AVAudioPlayer?
    private var holdPlayer: AVAudioSourceNode?
    private var holdFrequency: Double = 220
    private var holdPhase: Double = 0
    private let sampleRate: Double = 44100

    private init() {
        mixer = engine.mainMixerNode
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        try? engine.start()
    }

    private func playTone(frequency: Double, duration: Double, volume: Float, waveform: Waveform = .sine) {
        guard isEnabled else { return }
        let format = mixer.outputFormat(forBus: 0)
        var phase: Double = 0
        let phaseIncrement = 2.0 * .pi * frequency / sampleRate
        let totalFrames = Int(duration * sampleRate)
        var framesRendered = 0

        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let progress = Double(framesRendered) / Double(totalFrames)
                let envelope = progress >= 1.0 ? 0.0 : (1.0 - progress) // fade out lineal simple
                let sampleValue: Double
                switch waveform {
                case .sine: sampleValue = sin(phase)
                case .triangle: sampleValue = 2.0 / .pi * asin(sin(phase))
                }
                let value = Float(sampleValue) * volume * Float(envelope)
                for buffer in ablPointer {
                    let bufPtr = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < bufPtr.count { bufPtr[frame] = value }
                }
                phase += phaseIncrement
                if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                framesRendered += 1
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: mixer, format: format)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            self?.engine.detach(source)
        }
    }

    private enum Waveform { case sine, triangle }

    /// Click corto para botones normales (login, elegir entorno/modo, ejecutar, limpiar).
    func playClick() {
        playTone(frequency: 720, duration: 0.08, volume: 0.18)
    }

    /// Chime de confirmacion (dos notas), al completar una inyeccion con exito o subir de rango.
    func playChime() {
        playTone(frequency: 660, duration: 0.32, volume: 0.22, waveform: .triangle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            self?.playTone(frequency: 990, duration: 0.32, volume: 0.22, waveform: .triangle)
        }
    }

    /// Voz de confirmación que se reproduce cuando la inyección termina correctamente.
    func playActivationVoice() {
        guard isEnabled, activationVoiceEnabled,
              let url = Bundle.main.url(forResource: "opcion_activada", withExtension: "mp3") else { return }
        do {
            activationPlayer?.stop()
            activationPlayer = try AVAudioPlayer(contentsOf: url)
            activationPlayer?.volume = 1.0
            activationPlayer?.prepareToPlay()
            activationPlayer?.play()
        } catch {
            activationPlayer = nil
        }
    }

    // MARK: - Tono continuo del hold-to-confirm (sube de tono mientras se mantiene presionado)

    func startHoldTone() {
        guard isEnabled else { return }
        stopHoldTone()
        holdFrequency = 220
        holdPhase = 0
        let format = mixer.outputFormat(forBus: 0)
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = 2.0 * .pi * self.holdFrequency / self.sampleRate
            for frame in 0..<Int(frameCount) {
                let value = Float(sin(self.holdPhase)) * 0.09
                for buffer in ablPointer {
                    let bufPtr = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < bufPtr.count { bufPtr[frame] = value }
                }
                self.holdPhase += phaseIncrement
                if self.holdPhase > 2.0 * .pi { self.holdPhase -= 2.0 * .pi }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: mixer, format: format)
        holdPlayer = node
    }

    /// pct: 0...100, progreso del hold. La frecuencia sube de 220Hz a 880Hz.
    func updateHoldTone(pct: Double) {
        holdFrequency = 220 + (pct / 100.0) * 660
    }

    func stopHoldTone() {
        guard let node = holdPlayer else { return }
        engine.detach(node)
        holdPlayer = nil
    }
}

// MARK: - Haptics — feedback fisico real, no tiene equivalente en el HTML

enum HapticsService {
    static var isEnabled: Bool = true

    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
