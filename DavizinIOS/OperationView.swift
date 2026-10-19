import UIKit

protocol OperationViewDelegate: AnyObject {
    func operationView(_ view: OperationView, didTap operation: DavizinOperationKind)
}

final class OperationView: UIView {
    weak var delegate: OperationViewDelegate?

    private let cardView = DavizinCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checklistLabel = UILabel()
    private let noticeCard = UIView()
    private let noticeTitleLabel = UILabel()
    private let noticeBodyLabel = UILabel()
    private let noticeStack = UIStackView()
    private let successCard = UIView()
    private let successLabel = UILabel()

    // Estado 1 (antes de inyectar): solo estos dos son visibles.
    private let runButton = DavizinButton(title: "PREPARAR ENTORNO", style: .secondary)
    private let injectButton = DavizinButton(title: "MANTÉN PARA INYECTAR", style: .primary)

    // Estado 2 (despues de inyectar con exito): solo estos dos son visibles.
    private let cleanButton = DavizinButton(title: "LIMPIAR SESIÓN", style: .destructive)
    private let openGameButton = DavizinButton(title: "ABRIR JUEGO")
    var onOpenGame: (() -> Void)?

    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let statusRow = UIStackView()
    private let stackView = UIStackView()

    // Hold-to-confirm: anillo de progreso sobre injectButton
	private let holdRingLayer = CAShapeLayer()
	private var holdTimer: Timer?
    private var holdProgress: CGFloat = 0
	// Tiempo reducido para que el botón responda más rápido sin activarse con
	// un toque accidental.
	private let holdDuration: TimeInterval = 0.32
    private var isHoldingInject = false
    private var openGameFailureMessage: String?

    private(set) var operationState: DavizinOperationState = .idle

    private func setStatusIndicator(color: UIColor, pulse: Bool) {
        statusDot.backgroundColor = color
        statusDot.layer.shadowColor = color.cgColor
        statusDot.layer.shadowRadius = pulse ? 5.0 : 3.0
        statusDot.layer.shadowOpacity = pulse ? 0.55 : 0.30
        statusDot.layer.removeAllAnimations()
        guard pulse else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.38
        animation.toValue = 1.0
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        statusDot.layer.add(animation, forKey: "nyxel.statusPulse")
    }

    private func showSuccessPulse() {
        let originalTransform = cardView.transform
        cardView.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        UIView.animate(withDuration: 0.22, delay: 0.0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.cardView.transform = CGAffineTransform(scaleX: 1.012, y: 1.012)
        } completion: { _ in
            UIView.animate(withDuration: 0.24, delay: 0.0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.cardView.transform = originalTransform
            }
        }
    }

    var selectedGame: DavizinGame = .freeFireMax {
        didSet { updateSubtitle() }
    }

    var selectedMode: DavizinMode? {
        didSet {
            updateSubtitle()
            updateNotice()
            showPreInjectButtons(animated: false)
        }
    }

    func setPreflight(_ lines: [String]) {
        checklistLabel.text = "VERIFICACIÓN\n" + lines.joined(separator: "\n")
    }

    func setCleanupRecoveryMode() {
        titleLabel.text = "RECUPERACIÓN DE SESIÓN"
        subtitleLabel.text = "Completa la limpieza pendiente antes de volver a inyectar."
        noticeCard.isHidden = true
        runButton.isHidden = true
        injectButton.isHidden = true
        successCard.isHidden = true
        checklistLabel.text = "ACCIÓN OBLIGATORIA\nLa restauración debe confirmarse antes de continuar."
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setState(_ state: DavizinOperationState) {
        operationState = state
        successCard.isHidden = true
        statusLabel.textColor = AppTheme.secondaryText
        runButton.setLoading(false)
        cleanButton.setLoading(false)

        switch state {
        case .idle:
            setStatusIndicator(color: AppTheme.accent, pulse: false)
            statusLabel.text = nil
            statusLabel.isHidden = true
            statusRow.isHidden = true
        case .checking:
            setStatusIndicator(color: AppTheme.accent, pulse: true)
            statusLabel.text = "Comprobando el entorno..."
            statusLabel.isHidden = false
            statusRow.isHidden = false
        case .running:
            setStatusIndicator(color: AppTheme.warm, pulse: true)
            runButton.setLoading(true, title: "PREPARANDO...")
            statusLabel.text = "Preparando el entorno..."
            statusLabel.isHidden = false
            statusRow.isHidden = false
        case .injecting:
            setStatusIndicator(color: AppTheme.accentHot, pulse: true)
            statusLabel.text = "Aplicando la configuración..."
            statusLabel.isHidden = false
            statusRow.isHidden = false
        case .cleaning:
            setStatusIndicator(color: AppTheme.warm, pulse: true)
            cleanButton.setLoading(true, title: "LIMPIANDO...")
            statusLabel.text = "Limpiando la sesión..."
            statusLabel.isHidden = false
            statusRow.isHidden = false
        case .succeeded(let message):
            setStatusIndicator(color: AppTheme.success, pulse: false)
            statusLabel.text = message
            statusLabel.textColor = AppTheme.success
            statusLabel.isHidden = false
            statusRow.isHidden = false
            if message.lowercased().contains("inyectado") {
                successCard.isHidden = false
                showSuccessPulse()
                HapticsService.success()
                SoundService.shared.playActivationVoice()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    SoundService.shared.playChime()
                }
                SessionStats.recordInjection()
                showPostInjectButtons(animated: true)
            } else {
                // Exito de "Ejecutar" o "Limpiar" -> se queda/regresa al estado pre-inyeccion.
                showPreInjectButtons(animated: true)
            }
        case .failed(let message):
            setStatusIndicator(color: AppTheme.failure, pulse: false)
            statusLabel.text = message
            statusLabel.textColor = AppTheme.failure
            statusLabel.isHidden = false
            statusRow.isHidden = false
            HapticsService.warning()
        }

        let enabled = !state.isBusy
        runButton.isEnabled = enabled
        injectButton.isEnabled = enabled
        cleanButton.isEnabled = enabled
        openGameButton.isEnabled = enabled
        if enabled, NyxelCleanupFlow.hasPendingWork {
            applyCleanupStage(NyxelCleanupFlow.stage)
        }
    }

    func setProgressMessage(_ message: String) {
        guard case .injecting = operationState else { return }
        statusLabel.text = message
        statusLabel.isHidden = false
        statusRow.isHidden = false
    }

    func setOpeningGame(_ opening: Bool) {
        openGameButton.setLoading(opening, title: "ABRIENDO JUEGO...")
        openGameButton.isEnabled = !opening
        if opening {
            openGameFailureMessage = nil
            setStatusIndicator(color: AppTheme.accent, pulse: true)
            statusLabel.text = "Intentando abrir \(selectedGame.rawValue)..."
            statusLabel.textColor = AppTheme.accent
            statusLabel.isHidden = false
            statusRow.isHidden = false
        }
    }

    func showGameOpenResult(success: Bool) {
        openGameButton.setLoading(false)
        openGameButton.isEnabled = true
        openGameFailureMessage = success ? nil : "NYX-004 — No se pudo abrir el juego; puedes volver a intentarlo."
        setStatusIndicator(color: success ? AppTheme.success : AppTheme.failure, pulse: false)
        statusLabel.text = success
            ? "Juego abierto correctamente ✓"
            : "NYX-004 — No se pudo abrir el juego"
        statusLabel.textColor = success ? AppTheme.success : AppTheme.failure
        statusLabel.isHidden = false
        statusRow.isHidden = false
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = ""
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.font = AppTheme.titleFont(22)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.textColor = AppTheme.secondaryText
        subtitleLabel.font = AppTheme.bodyFont()
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isHidden = false
        updateSubtitle()

        checklistLabel.font = AppTheme.monoFont(10)
        checklistLabel.textColor = AppTheme.secondaryText
        checklistLabel.numberOfLines = 0
        checklistLabel.text = "VERIFICACIÓN\n✓ Sesión activa\n✓ Modo remoto seleccionado"

        noticeTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        noticeTitleLabel.numberOfLines = 0
        noticeBodyLabel.font = AppTheme.captionFont()
        noticeBodyLabel.numberOfLines = 0
        noticeStack.axis = .vertical
        noticeStack.spacing = 4.0
        noticeStack.translatesAutoresizingMaskIntoConstraints = false
        noticeStack.addArrangedSubview(noticeTitleLabel)
        noticeStack.addArrangedSubview(noticeBodyLabel)
        noticeCard.layer.cornerRadius = 10.0
        noticeCard.layer.borderWidth = 1.0
        noticeCard.layer.masksToBounds = true
        noticeCard.addSubview(noticeStack)
        NSLayoutConstraint.activate([
            noticeStack.leadingAnchor.constraint(equalTo: noticeCard.leadingAnchor, constant: 12.0),
            noticeStack.trailingAnchor.constraint(equalTo: noticeCard.trailingAnchor, constant: -12.0),
            noticeStack.topAnchor.constraint(equalTo: noticeCard.topAnchor, constant: 10.0),
            noticeStack.bottomAnchor.constraint(equalTo: noticeCard.bottomAnchor, constant: -10.0)
        ])
        updateNotice()

        successLabel.text = "✓  CONFIGURACIÓN ACTIVADA"
        successLabel.textColor = AppTheme.success
        successLabel.font = .systemFont(ofSize: 14, weight: .black)
        successLabel.textAlignment = .center
        successLabel.translatesAutoresizingMaskIntoConstraints = false
        successCard.backgroundColor = AppTheme.success.withAlphaComponent(0.12)
        successCard.layer.cornerRadius = 12.0
        successCard.layer.borderWidth = 1.0
        successCard.layer.borderColor = AppTheme.success.withAlphaComponent(0.48).cgColor
        successCard.addSubview(successLabel)
        successCard.accessibilityLabel = "Opción activada correctamente"
        successCard.isAccessibilityElement = true
        successCard.isHidden = true
        NSLayoutConstraint.activate([
            successCard.heightAnchor.constraint(equalToConstant: 48.0),
            successLabel.leadingAnchor.constraint(equalTo: successCard.leadingAnchor, constant: 12.0),
            successLabel.trailingAnchor.constraint(equalTo: successCard.trailingAnchor, constant: -12.0),
            successLabel.centerYAnchor.constraint(equalTo: successCard.centerYAnchor)
        ])

        runButton.accessibilityIdentifier = "operation.runExploit"
        runButton.accessibilityLabel = "Preparar entorno"
        injectButton.accessibilityIdentifier = "operation.inject"
        injectButton.accessibilityLabel = "Mantener presionado para activar la configuración"
        cleanButton.accessibilityIdentifier = "operation.clean"
        cleanButton.accessibilityLabel = "Limpiar sesión"
        openGameButton.accessibilityIdentifier = "operation.opengame"
        openGameButton.accessibilityLabel = "Abrir juego"

        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        cleanButton.addTarget(self, action: #selector(cleanTapped), for: .touchUpInside)
        openGameButton.addTarget(self, action: #selector(openGameTapped), for: .touchUpInside)

		// Eventos directos de UIButton son más confiables que un
		// UILongPressGestureRecognizer con duración cero: no se pierde el toque
		// cuando el dedo se mueve ligeramente o la vista está animándose.
		injectButton.addTarget(self, action: #selector(injectTouchDown), for: .touchDown)
		injectButton.addTarget(self, action: #selector(injectTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
		setupHoldRing()

        statusLabel.textColor = AppTheme.secondaryText
        statusLabel.font = AppTheme.captionFont()
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.layer.cornerRadius = 4.0
        statusDot.layer.shadowOffset = .zero
        statusDot.widthAnchor.constraint(equalToConstant: 8.0).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8.0).isActive = true
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 7.0
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addArrangedSubview(statusDot)
        statusRow.addArrangedSubview(statusLabel)
        statusRow.isHidden = true

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(checklistLabel)
        stackView.addArrangedSubview(noticeCard)
        stackView.addArrangedSubview(runButton)
        stackView.addArrangedSubview(injectButton)
        stackView.addArrangedSubview(successCard)
        stackView.addArrangedSubview(cleanButton)
        stackView.addArrangedSubview(openGameButton)
        stackView.addArrangedSubview(statusRow)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.useTransparentAppearance()
        cardView.addContent(stackView)
        addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 22.0),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22.0),
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 600.0 : AppTheme.contentMaximumWidth),
            stackView.widthAnchor.constraint(greaterThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 380.0 : 240.0),
            runButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight),
            injectButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight),
            cleanButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight),
            openGameButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight)
        ])

        showPreInjectButtons(animated: false)
    }

    // MARK: - Maquina de estados de botones

    func showPreInjectButtons(animated: Bool) {
        injectButton.setTitle("MANTÉN PARA INYECTAR", for: .normal)
        setButtonsVisible(run: true, inject: true, clean: false, openGame: false, animated: animated)
    }

    private func showPostInjectButtons(animated: Bool) {
        setButtonsVisible(run: false, inject: false, clean: true, openGame: true, animated: animated)
    }

    func applyCleanupStage(_ stage: NyxelCleanupStage) {
        guard stage != .idle else {
            cleanButton.setTitle("LIMPIAR SESIÓN", for: .normal)
            showPreInjectButtons(animated: false)
            return
        }

        runButton.isEnabled = false
        injectButton.isEnabled = false
        statusLabel.isHidden = false
        statusRow.isHidden = false

        switch stage {
        case .idle:
            break
        case .readyToOpen:
            cleanButton.setTitle("LIMPIAR SESIÓN", for: .normal)
            setStatusIndicator(color: AppTheme.success, pulse: false)
            statusLabel.text = "Configuración lista. Abre el juego."
            statusLabel.textColor = AppTheme.success
            checklistLabel.text = "SIGUIENTE PASO\n✓ Abre Free Fire y espera 8–10 segundos.\n✓ Regresa a Nyxel para limpiar la sesión."
            setButtonsVisible(run: false, inject: false, clean: false, openGame: true, animated: false)
            openGameButton.setTitle("ABRIR JUEGO", for: .normal)
            openGameButton.isEnabled = !operationState.isBusy
            cleanButton.isEnabled = false
        case .waitingForReturn:
            setStatusIndicator(color: AppTheme.warm, pulse: true)
            statusLabel.text = "Vuelve a Nyxel y limpia la sesión sí o sí."
            statusLabel.textColor = AppTheme.warm
            checklistLabel.text = "ACCIÓN OBLIGATORIA\nVuelve a Nyxel y pulsa LIMPIAR SESIÓN. Si no ves el aviso, regresa manualmente."
            setButtonsVisible(run: false, inject: false, clean: true, openGame: false, animated: false)
            cleanButton.setTitle("REGRESA A NYXEL", for: .normal)
            cleanButton.isEnabled = false
            openGameButton.isEnabled = false
        case .needsCleaning:
            setStatusIndicator(color: AppTheme.failure, pulse: true)
            statusLabel.text = "Limpia sesión sí o sí antes de continuar."
            statusLabel.textColor = AppTheme.failure
            checklistLabel.text = "ACCIÓN OBLIGATORIA\nNo vuelvas a inyectar hasta que la restauración termine correctamente."
            setButtonsVisible(run: false, inject: false, clean: true, openGame: false, animated: false)
            cleanButton.setTitle("LIMPIAR SESIÓN SÍ O SÍ", for: .normal)
            cleanButton.isEnabled = !operationState.isBusy
            openGameButton.isEnabled = false
        case .readyToReopen:
            cleanButton.setTitle("LIMPIAR SESIÓN", for: .normal)
            setStatusIndicator(color: AppTheme.success, pulse: false)
            statusLabel.text = "Limpieza confirmada. Abre Free Fire otra vez."
            statusLabel.textColor = AppTheme.success
            checklistLabel.text = "ÚLTIMO PASO\n✓ La limpieza terminó. Vuelve a abrir el juego."
            setButtonsVisible(run: false, inject: false, clean: false, openGame: true, animated: false)
            openGameButton.setTitle("VOLVER A ABRIR JUEGO", for: .normal)
            openGameButton.isEnabled = !operationState.isBusy
            cleanButton.isEnabled = false
        }

        if case .failed(let message) = operationState {
            statusLabel.text = message
            statusLabel.textColor = AppTheme.failure
        }
        if let openGameFailureMessage {
            statusLabel.text = openGameFailureMessage
            statusLabel.textColor = AppTheme.failure
        }
    }

    private func setButtonsVisible(run: Bool, inject: Bool, clean: Bool, openGame: Bool, animated: Bool) {
        let apply = {
            self.runButton.isHidden = !run
            self.injectButton.isHidden = !inject
            self.cleanButton.isHidden = !clean
            self.openGameButton.isHidden = !openGame
            self.runButton.alpha = run ? 1 : 0
            self.injectButton.alpha = inject ? 1 : 0
            self.cleanButton.alpha = clean ? 1 : 0
            self.openGameButton.alpha = openGame ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: AppTheme.durationModal, delay: 0, options: [.curveEaseOut], animations: apply)
        } else {
            apply()
        }
    }

    private func updateSubtitle() {
        titleLabel.text = "\(selectedGame.rawValue) / \(selectedMode?.displayName ?? "Modo no disponible")"
        subtitleLabel.text = "Prepara el entorno y mantén presionado para activar la configuración."
    }

    private func updateNotice() {
        guard let selectedMode else {
            noticeCard.isHidden = true
            return
        }
        let visible = selectedMode.noticeEnabled && !selectedMode.noticeTitle.isEmpty && !selectedMode.noticeBody.isEmpty
        noticeCard.isHidden = !visible
        guard visible else { return }
        let tint: UIColor
        switch selectedMode.noticeLevel.lowercased() {
        case "green": tint = AppTheme.success
        case "red": tint = AppTheme.failure
        default: tint = AppTheme.warm
        }
        noticeCard.backgroundColor = tint.withAlphaComponent(0.12)
        noticeCard.layer.borderColor = tint.withAlphaComponent(0.55).cgColor
        noticeTitleLabel.textColor = tint
        noticeBodyLabel.textColor = AppTheme.secondaryText
        noticeTitleLabel.text = selectedMode.noticeTitle
        noticeBodyLabel.text = selectedMode.noticeBody
    }

    // MARK: - Hold-to-confirm

    private func setupHoldRing() {
        holdRingLayer.strokeColor = AppTheme.accentHot.cgColor
        holdRingLayer.fillColor = UIColor.clear.cgColor
        holdRingLayer.lineWidth = 3
        holdRingLayer.strokeEnd = 0
        holdRingLayer.opacity = 0
        injectButton.layer.addSublayer(holdRingLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = injectButton.bounds
        guard bounds.width > 0 else { return }
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: AppTheme.controlCornerRadius)
        holdRingLayer.path = path.cgPath
        holdRingLayer.frame = bounds
    }

	@objc private func injectTouchDown() {
		guard injectButton.isEnabled, !isHoldingInject else { return }
		isHoldingInject = true
		startHold()
	}

	@objc private func injectTouchUp() {
		guard isHoldingInject else { return }
		isHoldingInject = false
		if holdProgress < 1.0 {
			cancelHold()
		}
	}

    private func startHold() {
        holdProgress = 0
        injectButton.setTitle("PREPARANDO...", for: .normal)
        holdRingLayer.opacity = 1
        SoundService.shared.startHoldTone()
        HapticsService.light()
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.holdProgress += CGFloat(1.0 / 60.0 / self.holdDuration)
            self.holdRingLayer.strokeEnd = min(self.holdProgress, 1.0)
            SoundService.shared.updateHoldTone(pct: Double(min(self.holdProgress, 1.0)) * 100)
            if self.holdProgress >= 1.0 {
                timer.invalidate()
                self.holdTimer = nil
                self.completeHold()
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        SoundService.shared.stopHoldTone()
        injectButton.setTitle("MANTÉN PARA INYECTAR", for: .normal)
        UIView.animate(withDuration: 0.2) {
            self.holdRingLayer.strokeEnd = 0
            self.holdRingLayer.opacity = 0
        }
    }

	private func completeHold() {
		isHoldingInject = false
		SoundService.shared.stopHoldTone()
        injectButton.setTitle("INYECTANDO...", for: .normal)
        UIView.animate(withDuration: 0.15) {
            self.holdRingLayer.opacity = 0
        } completion: { _ in
            self.holdRingLayer.strokeEnd = 0
        }
        delegate?.operationView(self, didTap: .inject)
    }

    @objc private func runTapped() {
        delegate?.operationView(self, didTap: .runExploit)
    }

    @objc private func cleanTapped() {
        delegate?.operationView(self, didTap: .clean)
    }

    @objc private func openGameTapped() {
        SoundService.shared.playClick()
        onOpenGame?()
    }
}
