import UIKit

// MARK: - DavizinButton v2
// Press feedback: scale(0.97), 150ms — recipe "Button press" de animate/RECIPES.md,
// portado a UIKit con spring en vez de cubic-bezier (nativo UIKit no anima bien
// cubic-bezier + transform combinados en highlighted state, spring da mejor feel físico).

enum DavizinButtonStyle {
    case primary
    case secondary
    case destructive
}

final class DavizinButton: UIButton {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var titleBeforeLoading: String?
    private var style: DavizinButtonStyle = .secondary
    private var usesLoginEmphasis = false
    private let loginGradient = CAGradientLayer()

    var selectedVisual: Bool = false {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
            // Recipe "Button press": scale(0.97), no scale(0) nunca.
            UIView.animate(
                withDuration: AppTheme.durationButtonPress,
                delay: 0.0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    convenience init(title: String, style: DavizinButtonStyle = .secondary) {
        self.init(type: .system)
        self.style = style
        setTitle(title, for: .normal)
        configure()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        loginGradient.frame = bounds
        loginGradient.cornerRadius = layer.cornerRadius
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        updateAppearance()
    }

    func setButtonStyle(_ style: DavizinButtonStyle) {
        self.style = style
        updateAppearance()
    }

    func useLoginEmphasis() {
        usesLoginEmphasis = true
        if loginGradient.superlayer == nil {
            loginGradient.startPoint = CGPoint(x: 0.0, y: 0.0)
            loginGradient.endPoint = CGPoint(x: 1.0, y: 1.0)
            layer.insertSublayer(loginGradient, at: 0)
        }
        updateAppearance()
    }

    func setLoading(_ loading: Bool, title: String? = nil) {
        if loading {
            titleBeforeLoading = currentTitle
            isEnabled = false
            setTitle(title ?? currentTitle, for: .normal)
            spinner.startAnimating()
            spinner.isHidden = false
            accessibilityValue = title ?? "Cargando"
        } else {
            spinner.stopAnimating()
            spinner.isHidden = true
            isEnabled = true
            if let titleBeforeLoading = titleBeforeLoading {
                setTitle(titleBeforeLoading, for: .normal)
            }
            titleBeforeLoading = nil
            accessibilityValue = nil
        }
        updateAppearance()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel?.font = AppTheme.controlFont()
        titleLabel?.adjustsFontForContentSizeCategory = true
        layer.cornerRadius = AppTheme.controlCornerRadius
        layer.cornerCurve = .continuous
        contentEdgeInsets = UIEdgeInsets(top: 14.0, left: 18.0, bottom: 14.0, right: 18.0)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18.0)
        ])
        updateAppearance()
    }

    private func updateAppearance() {
        let baseColor: UIColor
        let titleColor: UIColor
        let borderColor: UIColor

        switch style {
        case .primary:
            baseColor = AppTheme.readableAccent
            titleColor = AppTheme.accentForeground
            borderColor = AppTheme.readableAccent
        case .secondary:
            baseColor = selectedVisual ? AppTheme.readableAccent : AppTheme.control
            titleColor = selectedVisual ? AppTheme.accentForeground : AppTheme.primaryText
            borderColor = selectedVisual ? AppTheme.readableAccent : AppTheme.hairlineStrong
        case .destructive:
            baseColor = UIColor(red: 0.20, green: 0.05, blue: 0.06, alpha: 1.0)
            titleColor = UIColor(red: 1.0, green: 0.55, blue: 0.48, alpha: 1.0)
            borderColor = AppTheme.failure.withAlphaComponent(0.45)
        }

        let enabledAlpha: CGFloat = isEnabled ? 1.0 : 0.45
        let highlightAlpha: CGFloat = isHighlighted ? 0.80 : 1.0
        let visualAlpha = enabledAlpha * highlightAlpha
        if usesLoginEmphasis && style == .primary {
            loginGradient.isHidden = false
            loginGradient.colors = [
                AppTheme.readableAccent.withAlphaComponent(0.40 * visualAlpha).cgColor,
                AppTheme.readableAccent.withAlphaComponent(0.82 * visualAlpha).cgColor,
                AppTheme.readableAccent.withAlphaComponent(visualAlpha).cgColor
            ]
            backgroundColor = UIColor.clear
        } else {
            loginGradient.isHidden = true
            backgroundColor = baseColor.withAlphaComponent(visualAlpha)
        }
        setTitleColor(titleColor.withAlphaComponent(visualAlpha), for: .normal)
        layer.borderWidth = selectedVisual || style != .secondary ? 1.0 : 0.0
        layer.borderColor = borderColor.withAlphaComponent(visualAlpha).cgColor
        layer.shadowColor = selectedVisual || style == .primary ? AppTheme.readableAccent.cgColor : UIColor.clear.cgColor
        layer.shadowOpacity = selectedVisual || style == .primary ? 0.28 : 0.0
        layer.shadowRadius = usesLoginEmphasis ? 18.0 : 14.0
        layer.shadowOffset = CGSize(width: 0, height: usesLoginEmphasis ? 7.0 : 6.0)
        spinner.color = titleColor
    }
}
