import UIKit
import Security

private enum NyxelKeychain {
    private static let service = "com.nyxel.session"
    private static let account = "login-key"

    static var key: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        let data = Data(value.uppercased().utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func remove() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

protocol LoginViewDelegate: AnyObject {
    func loginView(_ loginView: LoginView, didTapContinueWithKey key: String)
}

final class LoginView: UIView {
    weak var delegate: LoginViewDelegate?

    private let videoBackground = DavizinLoginVideoView()
    private let videoOverlay = UIView()
    private let videoGradient = CAGradientLayer()
    private let vignetteGradient = CAGradientLayer()
    private let cardView = DavizinCardView()
    private let logoMark = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let keyField = UITextField()
    private let keyVisibilityButton = UIButton(type: .system)
    private let continueButton = DavizinButton(title: "ENTRAR AL PANEL", style: .primary)
    private let statusLabel = UILabel()
    private let compatLabel = UILabel()
    private let readinessRow = UIStackView()
    private let readinessDot = UIView()
    private let readinessLabel = UILabel()
    private let stackView = UIStackView()
    private var hasPlayedEntrance = false
    private var keyboardObserverTokens: [NSObjectProtocol] = []
    private var showingValidationError = false
    private var portraitLayoutConstraints: [NSLayoutConstraint] = []
    private var landscapeLayoutConstraints: [NSLayoutConstraint] = []
    private var usesLandscapeLayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        keyboardObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoGradient.frame = videoOverlay.bounds
        vignetteGradient.frame = videoOverlay.bounds
        updateResponsiveLayoutIfNeeded()
    }

    private func updateResponsiveLayoutIfNeeded() {
        guard !portraitLayoutConstraints.isEmpty else { return }
        let landscape = bounds.width > bounds.height && bounds.width > 600.0
        guard landscape != usesLandscapeLayout else { return }
        usesLandscapeLayout = landscape
        NSLayoutConstraint.deactivate(landscape ? portraitLayoutConstraints : landscapeLayoutConstraints)
        NSLayoutConstraint.activate(landscape ? landscapeLayoutConstraints : portraitLayoutConstraints)
        UIView.animate(withDuration: 0.28, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.layoutIfNeeded()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasPlayedEntrance else { return }
        hasPlayedEntrance = true

        videoBackground.alpha = 0.0
        cardView.alpha = 0.0
        cardView.transform = CGAffineTransform(translationX: 0.0, y: 16.0)

        UIView.animate(withDuration: 0.70, delay: 0.04, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.videoBackground.alpha = 1.0
        }

        guard !UIAccessibility.isReduceMotionEnabled else {
            logoMark.alpha = 1.0
            logoMark.transform = .identity
            cardView.alpha = 1.0
            cardView.transform = .identity
            return
        }

        UIView.animate(
            withDuration: 1.35,
            delay: 0.72,
            options: [.autoreverse, .repeat, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.logoMark.alpha = 0.72
            self.logoMark.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }

        UIView.animate(
            withDuration: 0.62,
            delay: 0.18,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.25,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.cardView.alpha = 1.0
            self.cardView.transform = .identity
        }
    }

    private func observeKeyboard() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillHideNotification
        ]
        keyboardObserverTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.adjustForKeyboard(notification)
            }
        }
    }

    private func adjustForKeyboard(_ notification: Notification) {
        guard window != nil else { return }
        let keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)
            .map { convert($0.cgRectValue, from: nil) } ?? .zero
        let isHidden = notification.name == UIResponder.keyboardWillHideNotification || keyboardFrame.minY >= bounds.maxY
        let bottomPadding: CGFloat = 18.0
        let overlap = isHidden ? 0.0 : max(0.0, cardView.frame.maxY - (keyboardFrame.minY - bottomPadding))
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16).union([.beginFromCurrentState, .allowUserInteraction])

        UIView.animate(withDuration: duration, delay: 0.0, options: options) {
            self.cardView.transform = CGAffineTransform(translationX: 0.0, y: -overlap)
        }
    }

    func setChecking(_ checking: Bool) {
        keyField.isEnabled = !checking
        keyVisibilityButton.isEnabled = !checking
        continueButton.setLoading(checking, title: "VERIFICANDO...")
        if checking {
            clearValidationFeedback()
        }
        statusLabel.text = checking ? "Validando credenciales..." : nil
        statusLabel.textColor = AppTheme.secondaryText
        statusLabel.isHidden = !checking
        setReadiness(checking ? "VERIFICANDO" : "SISTEMA LISTO", color: checking ? AppTheme.warm : AppTheme.accent)
    }

    func setStatus(_ text: String?, success: Bool = false) {
        guard let text = text, !text.isEmpty else {
            clearValidationFeedback()
            statusLabel.text = nil
            statusLabel.isHidden = true
            return
        }

        if success {
            clearValidationFeedback()
            statusLabel.text = text
            statusLabel.textColor = AppTheme.success
            setReadiness("SESIÓN ACTIVA", color: AppTheme.success)
        } else {
            // Mantener una respuesta uniforme: no revelar si la key existe,
            // expiró, fue revocada o si el servidor rechazó el dispositivo.
            statusLabel.text = "No se pudo validar la sesión."
            statusLabel.textColor = AppTheme.failure
            showValidationError()
            setReadiness("SESIÓN NO VALIDADA", color: AppTheme.failure)
        }
        statusLabel.isHidden = false
    }

    func reset() {
        setChecking(false)
        setStatus(nil)
    }

    private func setReadiness(_ text: String, color: UIColor) {
        readinessLabel.text = text
        readinessLabel.textColor = color
        readinessDot.backgroundColor = color
        readinessDot.layer.shadowColor = color.cgColor
        readinessDot.layer.shadowOpacity = UIAccessibility.isReduceMotionEnabled ? 0.0 : 0.75
    }

    private func showValidationError() {
        showingValidationError = true
        keyField.layer.removeAnimation(forKey: "nyxel.key.borderPulse")
        keyField.layer.borderColor = AppTheme.failure.cgColor
        keyField.layer.shadowColor = AppTheme.failure.cgColor
        keyField.layer.shadowOpacity = 0.24
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0.0, -7.0, 7.0, -4.0, 4.0, 0.0]
        shake.keyTimes = [0.0, 0.18, 0.38, 0.58, 0.78, 1.0]
        shake.duration = 0.34
        shake.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cardView.layer.add(shake, forKey: "nyxel.validation.shake")
    }

    private func clearValidationFeedback() {
        guard showingValidationError else { return }
        showingValidationError = false
        cardView.layer.removeAnimation(forKey: "nyxel.validation.shake")
        keyField.layer.shadowColor = AppTheme.accent.cgColor
        keyField.layer.shadowOpacity = 0.0
        keyField.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
    }

    /// Muestra el estado de compatibilidad del dispositivo (verde/rojo/amarillo).
    func setCompatibility(_ text: String, color: UIColor) {
        compatLabel.text = text
        compatLabel.textColor = color
        compatLabel.isHidden = text.isEmpty
    }

    func playExitAnimation(completion: @escaping () -> Void) {
        keyField.resignFirstResponder()
        UIView.animate(
            withDuration: 0.30,
            delay: 0.0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.cardView.alpha = 0.0
            self.cardView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            self.videoBackground.alpha = 0.0
            self.videoBackground.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        } completion: { _ in
            completion()
        }
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        videoBackground.translatesAutoresizingMaskIntoConstraints = false
        videoBackground.isUserInteractionEnabled = false
        videoOverlay.translatesAutoresizingMaskIntoConstraints = false
        videoOverlay.isUserInteractionEnabled = false
        videoOverlay.backgroundColor = .clear
        videoGradient.colors = [
            UIColor.black.withAlphaComponent(0.20).cgColor,
            UIColor.black.withAlphaComponent(0.32).cgColor,
            UIColor.black.withAlphaComponent(0.80).cgColor
        ]
        videoGradient.locations = [0.0, 0.48, 1.0]
        videoGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        videoGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        videoOverlay.layer.addSublayer(videoGradient)
        vignetteGradient.colors = [
            UIColor.black.withAlphaComponent(0.30).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.22).cgColor
        ]
        vignetteGradient.locations = [0.0, 0.18, 0.72, 1.0]
        vignetteGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        vignetteGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        videoOverlay.layer.addSublayer(vignetteGradient)
        addSubview(videoBackground)
        addSubview(videoOverlay)
        sendSubviewToBack(videoBackground)

			logoMark.image = UIImage(named: "NyxelAvatar")
			logoMark.tintColor = nil
				logoMark.contentMode = .scaleAspectFit
			logoMark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24.0, weight: .bold)
			logoMark.layer.shadowColor = AppTheme.accent.cgColor
                logoMark.layer.cornerRadius = 15.0
				logoMark.layer.masksToBounds = true
				logoMark.layer.shadowRadius = 8.0
			logoMark.layer.shadowOpacity = 0.42
			logoMark.layer.shadowOffset = .zero
			logoMark.heightAnchor.constraint(equalToConstant: 30.0).isActive = true

		titleLabel.text = "NYXEL EXTERNAL"
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.font = AppTheme.titleFont()
		titleLabel.textAlignment = .center
	        titleLabel.adjustsFontForContentSizeCategory = true
	        applyTitleTracking(titleLabel, value: -0.25)

		subtitleLabel.text = "SECURE EXTERNAL ACCESS"
        subtitleLabel.textColor = AppTheme.secondaryText
        subtitleLabel.font = AppTheme.bodyFont()
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        keyField.textColor = AppTheme.primaryText
        keyField.tintColor = AppTheme.primaryText
        keyField.font = AppTheme.bodyFont()
        keyField.layer.cornerRadius = AppTheme.controlCornerRadius
        keyField.layer.cornerCurve = .continuous
        keyField.layer.borderWidth = 1.0
        keyField.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        keyField.layer.shadowColor = AppTheme.accent.cgColor
        keyField.layer.shadowOffset = .zero
        keyField.layer.shadowRadius = 12.0
        keyField.layer.shadowOpacity = 0.0
        keyField.attributedPlaceholder = NSAttributedString(
            string: "INGRESA TU KEY DE ACCESO",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.42)]
        )
        keyField.isSecureTextEntry = true
        keyField.autocorrectionType = .no
        keyField.autocapitalizationType = .allCharacters
        keyField.returnKeyType = .continue
        keyField.clearButtonMode = .whileEditing
        keyField.accessibilityLabel = "Key de acceso"
        keyField.accessibilityHint = "Pega tu key; los espacios y saltos de línea se eliminan automáticamente"
        keyField.delegate = self
        keyField.addTarget(self, action: #selector(keyFieldChanged), for: .editingChanged)
		keyField.text = NyxelKeychain.key
        keyField.setLeftPadding(14.0)
        keyVisibilityButton.setImage(UIImage(systemName: "eye.slash.fill"), for: .normal)
        keyVisibilityButton.tintColor = UIColor.white.withAlphaComponent(0.58)
        keyVisibilityButton.frame = CGRect(x: 0.0, y: 0.0, width: 42.0, height: AppTheme.controlHeight)
        keyVisibilityButton.accessibilityLabel = "Mostrar key"
        keyVisibilityButton.addTarget(self, action: #selector(toggleKeyVisibility), for: .touchUpInside)
        keyField.rightView = keyVisibilityButton
        keyField.rightViewMode = .always
        keyField.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight).isActive = true

        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        continueButton.useLoginEmphasis()
        continueButton.accessibilityIdentifier = "login.continue"

        statusLabel.textColor = AppTheme.secondaryText
        statusLabel.font = AppTheme.captionFont()
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        readinessDot.translatesAutoresizingMaskIntoConstraints = false
        readinessDot.layer.cornerRadius = 4.0
        readinessDot.layer.shadowRadius = 6.0
        readinessDot.layer.shadowOffset = .zero
        readinessDot.backgroundColor = AppTheme.accent
        readinessLabel.text = "SISTEMA LISTO"
        readinessLabel.textColor = AppTheme.accent
        readinessLabel.font = AppTheme.captionFont()
        readinessLabel.adjustsFontForContentSizeCategory = true
        readinessRow.axis = .horizontal
        readinessRow.alignment = .center
        readinessRow.spacing = 7.0
        readinessRow.translatesAutoresizingMaskIntoConstraints = false
        readinessRow.addArrangedSubview(readinessDot)
        readinessRow.addArrangedSubview(readinessLabel)
        readinessDot.widthAnchor.constraint(equalToConstant: 8.0).isActive = true
        readinessDot.heightAnchor.constraint(equalToConstant: 8.0).isActive = true

        compatLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .bold)
        compatLabel.textAlignment = .center
        compatLabel.numberOfLines = 0
        compatLabel.isHidden = true

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 14.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(logoMark)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(compatLabel)
        stackView.addArrangedSubview(keyField)
        stackView.addArrangedSubview(continueButton)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(readinessRow)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.useTransparentAppearance()
        cardView.addContent(stackView)
        addSubview(cardView)

        let dismissKeyboardTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissKeyboardTap.cancelsTouchesInView = false
        addGestureRecognizer(dismissKeyboardTap)
        observeKeyboard()

        let commonConstraints = [
            videoBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoBackground.topAnchor.constraint(equalTo: topAnchor),
            videoBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            videoOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoOverlay.topAnchor.constraint(equalTo: topAnchor),
            videoOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.widthAnchor.constraint(greaterThanOrEqualToConstant: 220.0),
            continueButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight)
        ]
        NSLayoutConstraint.activate(commonConstraints)

		portraitLayoutConstraints = [
			cardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 18.0),
			cardView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -18.0),
            cardView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
			cardView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
			cardView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 18.0),
			cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -18.0),
			cardView.widthAnchor.constraint(lessThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 560.0 : 380.0)
		]

        if UIDevice.current.userInterfaceIdiom == .pad {
            landscapeLayoutConstraints = [
                cardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 28.0),
                cardView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -28.0),
                cardView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
                cardView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
                cardView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 18.0),
                cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -18.0),
				cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 560.0)
            ]
        } else {
            landscapeLayoutConstraints = [
                cardView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -28.0),
                cardView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
                cardView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 18.0),
                cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -18.0),
                cardView.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, multiplier: 0.42),
                cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 380.0)
            ]
        }

        NSLayoutConstraint.activate(portraitLayoutConstraints)
    }

	@objc private func keyFieldChanged() {
			if showingValidationError { clearValidationFeedback() }
				let value = normalizedKey(keyField.text ?? "")
				keyField.text = value
				if value.isEmpty { NyxelKeychain.remove() } else { NyxelKeychain.save(value) }
	}

    private func normalizedKey(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).joined().uppercased()
    }

    @objc private func toggleKeyVisibility() {
        let wasFirstResponder = keyField.isFirstResponder
        let selectedRange = keyField.selectedTextRange
        keyField.isSecureTextEntry.toggle()
        let visible = !keyField.isSecureTextEntry
        keyVisibilityButton.setImage(UIImage(systemName: visible ? "eye.fill" : "eye.slash.fill"), for: .normal)
        keyVisibilityButton.accessibilityLabel = visible ? "Ocultar key" : "Mostrar key"
        if wasFirstResponder {
            keyField.becomeFirstResponder()
            keyField.selectedTextRange = selectedRange
        }
    }

    @objc private func dismissKeyboard() {
        endEditing(true)
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard textField === keyField else { return }
        let borderPulse = CABasicAnimation(keyPath: "borderColor")
        borderPulse.fromValue = UIColor.white.withAlphaComponent(0.22).cgColor
        borderPulse.toValue = AppTheme.accent.cgColor
        borderPulse.duration = 0.85
        borderPulse.autoreverses = true
        borderPulse.repeatCount = .greatestFiniteMagnitude
        keyField.layer.add(borderPulse, forKey: "nyxel.key.borderPulse")
        UIView.animate(withDuration: 0.18) {
            self.keyField.backgroundColor = UIColor.black.withAlphaComponent(0.18)
            self.keyField.layer.borderColor = AppTheme.accent.cgColor
            self.keyField.layer.shadowOpacity = 0.28
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField === keyField else { return }
        keyField.layer.removeAnimation(forKey: "nyxel.key.borderPulse")
        UIView.animate(withDuration: 0.18) {
            self.keyField.backgroundColor = UIColor.black.withAlphaComponent(0.28)
            self.keyField.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
            self.keyField.layer.shadowOpacity = 0.0
        }
    }

    @objc private func continueTapped() {
        guard continueButton.isEnabled else { return }
        keyFieldChanged()
        keyField.resignFirstResponder()
        continueButton.isEnabled = false
        delegate?.loginView(self, didTapContinueWithKey: keyField.text ?? "")
    }
}

extension LoginView: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField === keyField,
              let current = textField.text,
              let textRange = Range(range, in: current) else { return true }

        let proposed = current.replacingCharacters(in: textRange, with: string)
        let normalized = normalizedKey(proposed)
        guard normalized != proposed || string.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return true
        }

        textField.text = normalized
        keyFieldChanged()
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        continueTapped()
        return true
    }
}

private extension UITextField {
    func setLeftPadding(_ padding: CGFloat) {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: padding, height: 1.0))
        leftView = container
        leftViewMode = .always
    }

    func setRightPadding(_ padding: CGFloat) {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: padding, height: 1.0))
        rightView = container
        rightViewMode = .always
    }
}
