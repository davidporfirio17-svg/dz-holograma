import UIKit

// MARK: - AppTheme — Nyxel External
// Dark premium utility: carbón profundo, texto cálido y un solo acento cian.
enum AppTheme {
    private static func adaptive(dark: UIColor, light: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .light ? light : dark }
    }
    static var background: UIColor { adaptive(dark: UIColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1.0), light: UIColor(red: 0.955, green: 0.965, blue: 0.980, alpha: 1.0)) }
    static var backgroundRaise: UIColor { adaptive(dark: UIColor(red: 0.055, green: 0.070, blue: 0.095, alpha: 1.0), light: UIColor.white) }
    static var card: UIColor { backgroundRaise }
    static var hairline: UIColor { adaptive(dark: UIColor.white.withAlphaComponent(0.09), light: UIColor.black.withAlphaComponent(0.10)) }
    static var hairlineStrong: UIColor { adaptive(dark: UIColor.white.withAlphaComponent(0.16), light: UIColor.black.withAlphaComponent(0.18)) }

    static var primaryText: UIColor { adaptive(dark: UIColor(red: 0.955, green: 0.970, blue: 0.985, alpha: 1.0), light: UIColor(red: 0.075, green: 0.095, blue: 0.135, alpha: 1.0)) }
    static var secondaryText: UIColor { adaptive(dark: UIColor(red: 0.800, green: 0.840, blue: 0.890, alpha: 0.72), light: UIColor(red: 0.220, green: 0.255, blue: 0.320, alpha: 0.78)) }
    static var tertiaryText: UIColor { adaptive(dark: UIColor(red: 0.700, green: 0.760, blue: 0.830, alpha: 0.42), light: UIColor(red: 0.300, green: 0.340, blue: 0.420, alpha: 0.60)) }

    private static let successDark = UIColor(red: 0.420, green: 0.820, blue: 0.690, alpha: 1.0)
    private static let failureDark = UIColor(red: 0.980, green: 0.360, blue: 0.400, alpha: 1.0)
    private static let warmDark = UIColor(red: 1.000, green: 0.680, blue: 0.260, alpha: 1.0)

    static var success: UIColor { readableSuccess }
    static var failure: UIColor { readableFailure }
    static var warm: UIColor { readableWarm }
    static var accentWarm: UIColor { readableWarm }

    static var accent: UIColor { readableAccent }
    static var accentHot: UIColor { readableAccent }
    static var accentDim: UIColor { NyxelAppearanceStore.accentDim }

    /// Colores de texto/acento con contraste suficiente sobre tarjetas claras.
    static var readableAccent: UIColor {
        UIColor { traits in
            guard traits.userInterfaceStyle == .light else { return NyxelAppearanceStore.accent }
            switch NyxelAppearanceStore.theme {
            case .cyan: return UIColor(red: 0.00, green: 0.40, blue: 0.31, alpha: 1.0)
            case .ember: return UIColor(red: 0.60, green: 0.19, blue: 0.04, alpha: 1.0)
            case .violet: return UIColor(red: 0.35, green: 0.18, blue: 0.63, alpha: 1.0)
            }
        }
    }
    static var accentForeground: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .light
                ? .white
                : UIColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1.0)
        }
    }
    static var readableSuccess: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor(red: 0.08, green: 0.39, blue: 0.25, alpha: 1.0)
                : successDark
        }
    }
    static var readableFailure: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor(red: 0.68, green: 0.13, blue: 0.20, alpha: 1.0)
                : failureDark
        }
    }
    static var readableWarm: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor(red: 0.54, green: 0.29, blue: 0.04, alpha: 1.0)
                : warmDark
        }
    }

    static var control: UIColor { card }
    static var separator: UIColor { hairline }

    static let cardCornerRadius:    CGFloat = 20.0
    static let controlCornerRadius: CGFloat = 14.0
    static let standardSpacing:     CGFloat = 16.0
    static let cardPadding:         CGFloat = 22.0
    static let contentMaximumWidth: CGFloat = 360.0
    static let controlHeight:       CGFloat = 52.0

    static func titleFont(_ size: CGFloat = 26) -> UIFont { UIFont.systemFont(ofSize: size, weight: .bold) }
    static func bodyFont()    -> UIFont { UIFont.systemFont(ofSize: 14, weight: .regular) }
    static func captionFont() -> UIFont { UIFont.systemFont(ofSize: 10, weight: .semibold) }
    static func controlFont() -> UIFont { UIFont.systemFont(ofSize: 14, weight: .semibold) }
    static func monoFont(_ size: CGFloat = 12) -> UIFont { UIFont.monospacedSystemFont(ofSize: size, weight: .medium) }

    static let titleTracking: CGFloat = -0.35
    static let durationButtonPress: TimeInterval = 0.15
    static let durationPopover: TimeInterval = 0.20
    static let durationModal: TimeInterval = 0.30
    static let durationDrawer: TimeInterval = 0.40

    static func easeOutTiming() -> UICubicTimingParameters {
        UICubicTimingParameters(controlPoint1: CGPoint(x: 0.22, y: 1.0), controlPoint2: CGPoint(x: 0.36, y: 1.0))
    }

    static func drawerTiming() -> UICubicTimingParameters {
        UICubicTimingParameters(controlPoint1: CGPoint(x: 0.32, y: 0.72), controlPoint2: CGPoint(x: 0.0, y: 1.0))
    }

    static func countdownColor(remainingSeconds: Int) -> UIColor {
        if remainingSeconds <= 3600 { return failure }
        if remainingSeconds <= 86400 { return warm }
        return success
    }
}

extension UIView {
    func davizinPinEdges(to view: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom)
        ])
    }

    func applyTitleTracking(_ label: UILabel, value: CGFloat = AppTheme.titleTracking) {
        guard let text = label.text else { return }
        let attr = NSMutableAttributedString(string: text)
        attr.addAttribute(.kern, value: value, range: NSRange(location: 0, length: text.count))
        label.attributedText = attr
    }
}
