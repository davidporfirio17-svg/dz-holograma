import SwiftUI
import AVFoundation

final class DavizinLoginVideoView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configure() {
        backgroundColor = .black
        clipsToBounds = true
        NotificationCenter.default.addObserver(self, selector: #selector(pauseVideo), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeVideo), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(motionPreferenceChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        start()
    }

    private func start() {
        guard !UIAccessibility.isReduceMotionEnabled,
              let url = Bundle.main.url(forResource: "login_background", withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer.player = queue
        playerLayer.videoGravity = .resizeAspectFill
        if window != nil { queue.play() }
    }

    @objc private func pauseVideo() { player?.pause() }

    @objc private func resumeVideo() {
        guard !UIAccessibility.isReduceMotionEnabled, window != nil else { return }
        player?.play()
    }

    @objc private func motionPreferenceChanged() {
        if UIAccessibility.isReduceMotionEnabled {
            player?.pause()
            playerLayer.player = nil
            player = nil
            looper = nil
        } else if player == nil {
            start()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { resumeVideo() } else { pauseVideo() }
    }
}

struct DavizinLoginVideoBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> DavizinLoginVideoView { DavizinLoginVideoView() }
    func updateUIView(_ uiView: DavizinLoginVideoView, context: Context) {}
}
