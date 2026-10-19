import UIKit

// MARK: - SplashViewController — presentación de marca Nyxel External.
final class SplashViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let portraitView = UIImageView()
    private let wordLabel = UILabel()
    private let captionLabel = UILabel()
    private let progressLayer = CAShapeLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppTheme.background

        portraitView.image = UIImage(named: "NyxelAvatar")
        portraitView.contentMode = .scaleAspectFill
        portraitView.clipsToBounds = true
        portraitView.layer.cornerRadius = 76
        portraitView.layer.cornerCurve = .continuous
        portraitView.layer.borderWidth = 1.0
        portraitView.layer.borderColor = AppTheme.accent.withAlphaComponent(0.48).cgColor
        portraitView.layer.shadowColor = AppTheme.accent.cgColor
        portraitView.layer.shadowRadius = 24
        portraitView.layer.shadowOpacity = 0.30
        portraitView.layer.shadowOffset = .zero
        portraitView.alpha = 0
        portraitView.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        portraitView.translatesAutoresizingMaskIntoConstraints = false

        wordLabel.text = "NYXEL EXTERNAL"
        wordLabel.font = .systemFont(ofSize: 15, weight: .bold)
        wordLabel.textColor = AppTheme.primaryText
        wordLabel.textAlignment = .center
        wordLabel.alpha = 0
        applyKerning(to: wordLabel, value: 2.4)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        captionLabel.text = "SECURE OPERATIONS"
        captionLabel.font = AppTheme.captionFont()
        captionLabel.textColor = AppTheme.tertiaryText
        captionLabel.textAlignment = .center
        captionLabel.alpha = 0
        applyKerning(to: captionLabel, value: 1.6)
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        let track = CAShapeLayer()
        let ringRect = CGRect(x: 0, y: 0, width: 164, height: 164)
        let path = UIBezierPath(ovalIn: ringRect.insetBy(dx: 4, dy: 4))
        track.path = path.cgPath
        track.frame = ringRect
        track.strokeColor = AppTheme.hairlineStrong.cgColor
        track.fillColor = UIColor.clear.cgColor
        track.lineWidth = 2

        progressLayer.path = path.cgPath
        progressLayer.frame = ringRect
        progressLayer.strokeColor = AppTheme.accent.cgColor
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineWidth = 2
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        portraitView.layer.addSublayer(track)
        portraitView.layer.addSublayer(progressLayer)

        view.addSubview(portraitView)
        view.addSubview(wordLabel)
        view.addSubview(captionLabel)

        NSLayoutConstraint.activate([
            portraitView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            portraitView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -34),
            portraitView.widthAnchor.constraint(equalToConstant: 152),
            portraitView.heightAnchor.constraint(equalToConstant: 152),
            wordLabel.topAnchor.constraint(equalTo: portraitView.bottomAnchor, constant: 28),
            wordLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captionLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 8),
            captionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateSplash()
    }

    private func animateSplash() {
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.85
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        progressLayer.add(draw, forKey: "draw")
        progressLayer.strokeEnd = 1

        UIView.animate(withDuration: 0.60, delay: 0.12, options: [.curveEaseOut]) {
            self.portraitView.alpha = 1
            self.portraitView.transform = .identity
        }
        UIView.animate(withDuration: 0.42, delay: 0.60, options: [.curveEaseOut]) {
            self.wordLabel.alpha = 1
            self.captionLabel.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.36, animations: {
                self.view.alpha = 0
            }, completion: { _ in self.onFinished?() })
        }
    }

    private func applyKerning(to label: UILabel, value: CGFloat) {
        guard let text = label.text else { return }
        let attr = NSMutableAttributedString(string: text)
        attr.addAttribute(.kern, value: value, range: NSRange(location: 0, length: text.count))
        label.attributedText = attr
    }
}
