import UIKit

// MARK: - DavizinToast — puerto nativo de Sonner (sonner-main/src/index.tsx + styles.css)
// Constantes copiadas literal del código fuente de Sonner, no inventadas:
//   VISIBLE_TOASTS_AMOUNT = 3, TOAST_LIFETIME = 4000, GAP = 14,
//   SWIPE_THRESHOLD = 45, TIME_BEFORE_UNMOUNT = 200
// Animación de entrada: scale(0.8)->scale(1), 300ms ease (@keyframes sonner-fade-in)

enum DavizinToastKind {
    case success, warning, danger

    var color: UIColor {
        switch self {
        case .success: return AppTheme.success
        case .warning: return UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        case .danger:  return AppTheme.failure
        }
    }
}

final class DavizinToastCenter {
    static let shared = DavizinToastCenter()
    private init() {}

    // Constantes literales de Sonner
    private let visibleToastsAmount = 3
    private let toastLifetime: TimeInterval = 4.0
    private let gap: CGFloat = 14.0
    private let swipeThreshold: CGFloat = 45.0
    private let timeBeforeUnmount: TimeInterval = 0.2

    private var window: UIWindow?
    private var activeToasts: [DavizinToastView] = []

    func show(title: String, subtitle: String? = nil, kind: DavizinToastKind = .success) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        if window == nil {
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            w.backgroundColor = .clear
            w.isHidden = false
            w.isUserInteractionEnabled = true
            let vc = UIViewController()
            vc.view.backgroundColor = .clear
            w.rootViewController = vc
            window = w
        }
        guard let container = window?.rootViewController?.view else { return }

        let toast = DavizinToastView(title: title, subtitle: subtitle, kind: kind)
        toast.onDismiss = { [weak self] in self?.remove(toast) }
        toast.swipeThreshold = swipeThreshold
        container.addSubview(toast)

        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
        ])

        activeToasts.append(toast)
        restack()

        // Entrada: scale 0.8 -> 1, 300ms ease — literal de sonner-fade-in
        toast.alpha = 0
        toast.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            toast.alpha = 1
            toast.transform = .identity
        }

        // Solo se ven las últimas `visibleToastsAmount` (igual que Sonner)
        if activeToasts.count > visibleToastsAmount {
            let overflow = activeToasts.count - visibleToastsAmount
            for i in 0..<overflow { activeToasts[i].alpha = 0.001 }
        }

        // Auto-dismiss a los 4000ms, se pausa si el usuario está tocando el toast
        toast.scheduleAutoDismiss(after: toastLifetime)
    }

    private func remove(_ toast: DavizinToastView) {
        guard let idx = activeToasts.firstIndex(where: { $0 === toast }) else { return }
        activeToasts.remove(at: idx)

        // Salida: 200ms — TIME_BEFORE_UNMOUNT exacto de Sonner
        UIView.animate(withDuration: timeBeforeUnmount, delay: 0, options: [.curveEaseInOut]) {
            toast.alpha = 0
            toast.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            toast.removeFromSuperview()
            self.restack()
            if self.activeToasts.isEmpty {
                self.window?.isHidden = true
                self.window = nil
            }
        }
    }

    /// Reacomoda el stack con el gap exacto de Sonner (14px) — el más nuevo abajo.
    private func restack() {
        var cumulativeOffset: CGFloat = 0
        for toast in activeToasts.reversed() {
            toast.bottomConstraintConstant = -(20 + cumulativeOffset)
            cumulativeOffset += toast.frame.height + gap
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                toast.superview?.layoutIfNeeded()
            }
        }
    }
}

final class DavizinToastView: UIView {
    var onDismiss: (() -> Void)?
    var swipeThreshold: CGFloat = 45.0
    var bottomConstraintConstant: CGFloat = -20 {
        didSet { bottomConstraint?.constant = bottomConstraintConstant }
    }

    private weak var bottomConstraint: NSLayoutConstraint?
    private var dismissTimer: Timer?
    private var remainingTime: TimeInterval = 4.0
    private var panStartTranslation: CGFloat = 0

    private let dot = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String?, kind: DavizinToastKind) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 4)

        dot.backgroundColor = kind.color
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0

        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.isHidden = subtitle == nil

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard let superview = superview,
              let bottom = constraints.first(where: { $0.firstAttribute == .bottom }) else { return }
        bottomConstraint = superview.constraints.first { $0.firstItem === self && $0.firstAttribute == .bottom }
    }

    func scheduleAutoDismiss(after seconds: TimeInterval) {
        remainingTime = seconds
        startTimer()
    }

    private func startTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
            self?.onDismiss?()
        }
    }

    private func pauseTimer() {
        dismissTimer?.invalidate()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self).x

        switch gesture.state {
        case .began:
            pauseTimer()
        case .changed:
            transform = CGAffineTransform(translationX: translation, y: 0)
            alpha = 1 - min(abs(translation) / 150, 0.6)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).x
            if abs(translation) > swipeThreshold || abs(velocity) > 500 {
                let direction: CGFloat = translation > 0 ? 1 : -1
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    self.transform = CGAffineTransform(translationX: direction * 500, y: 0)
                    self.alpha = 0
                } completion: { _ in
                    self.onDismiss?()
                }
            } else {
                UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3, options: [.allowUserInteraction]) {
                    self.transform = .identity
                    self.alpha = 1
                }
                startTimer()
            }
        default:
            break
        }
    }
}
