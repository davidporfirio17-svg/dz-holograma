import UIKit

final class ViewController: UIViewController {
    /// Actívalo en false cuando conectes tus propios callbacks de aplicación.
    var simulateUIStates = true

    /// Callbacks vacíos por defecto para conectar la lógica real desde fuera del UI.
    var onLoginContinue: ((String) -> Void)?
    var onGameSelected: ((DavizinGame) -> Void)?
    var onModeSelected: ((DavizinMode) -> Void)?
    var onOperation: ((DavizinOperationKind) -> Void)?
    var onClose: (() -> Void)?

    private let animatedBackgroundView = DavizinAnimatedBackgroundView()
    private let headerView = DavizinHeaderView()
    private let contentContainerView = UIView()
    private let bottomNavView = DavizinBottomNavView()
    private var bottomNavHeightConstraint: NSLayoutConstraint?

    private var currentStage: DavizinScreenStage = .login
    private var selectedGame: DavizinGame = .freeFireMax
    private var selectedMode: DavizinMode?
    private var activeKey: String?
    private var activeCountryCode: String?
    private var activeRemainingSeconds: Int = 0
    private var backgroundedAt: Date?
    private let inactivityLockInterval: TimeInterval = 10 * 60

    private var loginView: LoginView?
    private var gameSelectionView: GameSelectionView?
    private var missionMapView: MissionMapView?
    private var profileView: ProfileView?
    private var stageBeforeProfile: DavizinScreenStage = .modeSelection
    private var operationView: OperationView?

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .light ? .darkContent : .lightContent
    }

    /// Usa este factory cuando presentes el UI desde otro controlador.
    /// El estilo se fija antes de `present(...)`, que es el momento correcto para evitar `.pageSheet`.
    static func makeFullScreen() -> ViewController {
        let controller = ViewController()
        controller.modalPresentationStyle = .fullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        return controller
    }

    // MARK: - Public UI controls

    func showGameSelectionScreen() {
        showGameSelection(animated: true)
    }

    func showModeSelectionScreen() {
        showModeSelection(animated: true)
    }

    func showOperationScreen() {
        showOperation(animated: true)
    }

    func showCleanupRecoveryScreen(for game: DavizinGame, mode: DavizinMode? = nil) {
        selectedGame = game
        if let mode { selectedMode = mode }
        currentStage = .operation
        animatedBackgroundView.isHidden = false
        animatedBackgroundView.startAnimating()
        setBottomNavigation(visible: false, selected: .modes)
        headerView.title = "Recuperación obligatoria"
        headerView.showsBackButton = false
        headerView.showsAvatarButton = false

        let screen = OperationView()
        screen.delegate = self
        screen.selectedGame = game
        screen.selectedMode = mode ?? selectedMode
        screen.setCleanupRecoveryMode()
        screen.onOpenGame = { [weak self] in self?.openGame(game) }
        operationView = screen
        display(screen, animated: true)
        screen.applyCleanupStage(NyxelCleanupFlow.stage)
    }

    func setLoginChecking(_ checking: Bool) {
        loginView?.setChecking(checking)
    }

    func setLoginStatus(_ text: String?, success: Bool = false) {
        loginView?.setStatus(text, success: success)
    }

    func setOperationState(_ state: DavizinOperationState) {
        operationView?.setState(state)
        switch state {
        case .succeeded(let message):
            NyxelActivityLog.record("Operación completada")
            DavizinToastCenter.shared.show(title: "Operación completada", subtitle: message, kind: .success)
        case .failed(let message):
            NyxelActivityLog.record("Operación fallida")
            DavizinToastCenter.shared.show(title: "Operación fallida", subtitle: message, kind: .danger)
        default:
            break
        }
    }

    /// Actualiza el contador de tiempo restante en el header.
    func setCountdownText(_ text: String) {
        headerView.countdownText = text
    }

    func setCountdownColor(_ color: UIColor) {
        headerView.setCountdownColor(color)
    }

    func setAccountSession(key: String?, remainingSeconds: Int, countryCode: String? = nil) {
        activeKey = key
        if countryCode != nil { activeCountryCode = countryCode }
        if key == nil { activeCountryCode = nil }
        activeRemainingSeconds = max(0, remainingSeconds)
        profileView?.setAccount(key: key, remainingSeconds: activeRemainingSeconds, countryCode: activeCountryCode)
    }

    /// Muestra un mensaje personalizado del panel al cliente (popup con estilo Davizin).
    func showNotice(_ message: String, completion: @escaping () -> Void) {
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        overlay.alpha = 0.0

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = AppTheme.card
        card.layer.cornerRadius = AppTheme.cardCornerRadius
        card.layer.borderWidth = 1.0
        card.layer.borderColor = AppTheme.accent.withAlphaComponent(0.4).cgColor
        card.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)

        // Circulo con icono de campana
        let iconCircle = UIView()
        iconCircle.translatesAutoresizingMaskIntoConstraints = false
        iconCircle.backgroundColor = AppTheme.accent.withAlphaComponent(0.15)
        iconCircle.layer.cornerRadius = 32.0
        iconCircle.layer.borderWidth = 2.0
        iconCircle.layer.borderColor = AppTheme.accent.cgColor

        let iconView = UIImageView(image: UIImage(systemName: "bell.fill"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = AppTheme.accent
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Aviso"
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .bold)
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = message
        messageLabel.textColor = AppTheme.secondaryText
        messageLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let okButton = UIButton(type: .system)
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.setTitle("Entendido", for: .normal)
        okButton.setTitleColor(.white, for: .normal)
        okButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        okButton.backgroundColor = AppTheme.accent
        okButton.layer.cornerRadius = AppTheme.controlCornerRadius

        iconCircle.addSubview(iconView)
        card.addSubview(iconCircle)
        card.addSubview(titleLabel)
        card.addSubview(messageLabel)
        card.addSubview(okButton)
        overlay.addSubview(card)
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 32.0),
            card.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -32.0),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 340.0),

            iconCircle.topAnchor.constraint(equalTo: card.topAnchor, constant: 28.0),
            iconCircle.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconCircle.widthAnchor.constraint(equalToConstant: 64.0),
            iconCircle.heightAnchor.constraint(equalToConstant: 64.0),

            iconView.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28.0),
            iconView.heightAnchor.constraint(equalToConstant: 28.0),

            titleLabel.topAnchor.constraint(equalTo: iconCircle.bottomAnchor, constant: 16.0),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24.0),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24.0),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10.0),
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24.0),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24.0),

            okButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24.0),
            okButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24.0),
            okButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24.0),
            okButton.heightAnchor.constraint(equalToConstant: 50.0),
            okButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24.0)
        ])

        // Accion del boton: cerrar con animacion y continuar
        let dismissAction = UIAction { _ in
            UIView.animate(withDuration: 0.2, animations: {
                overlay.alpha = 0.0
                card.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            }) { _ in
                overlay.removeFromSuperview()
                completion()
            }
        }
        okButton.addAction(dismissAction, for: .touchUpInside)

        // Animacion de entrada
        UIView.animate(withDuration: 0.28, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
            overlay.alpha = 1.0
            card.transform = .identity
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = NyxelAppearanceStore.uiStyle
        configureBaseUI()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NyxelCleanupFlow.resetForFreshLaunch()
        showLogin(animated: false)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func appDidEnterBackground() { backgroundedAt = Date() }

    @objc private func appWillEnterForeground() {
        NyxelCleanupFlow.markReturnedToNyxel()
        if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) >= inactivityLockInterval {
            activeKey = nil
            activeRemainingSeconds = 0
            NyxelActivityLog.record("Sesión bloqueada por inactividad")
            showLogin(animated: true)
            return
        }
        if NyxelCleanupFlow.hasPendingWork, let game = NyxelCleanupFlow.game {
            showCleanupRecoveryScreen(for: game)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animatedBackgroundView.startAnimating()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        animatedBackgroundView.stopAnimating()
    }

    private func configureBaseUI() {
        view.backgroundColor = AppTheme.background

        animatedBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animatedBackgroundView)

        headerView.delegate = self
        view.addSubview(headerView)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = .clear
        view.addSubview(contentContainerView)

        bottomNavView.onModes = { [weak self] in
            self?.showModeSelection(animated: true)
        }
        bottomNavView.onProfile = { [weak self] in
            self?.showProfile(animated: true)
        }
        bottomNavView.onVPN = { [weak self] in
            self?.showVPN(animated: true)
        }
        view.addSubview(bottomNavView)
        let bottomNavHeight = bottomNavView.heightAnchor.constraint(equalToConstant: 0)
        bottomNavHeightConstraint = bottomNavHeight

        NSLayoutConstraint.activate([
            animatedBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            animatedBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            animatedBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            animatedBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.0),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.0),
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6.0),

            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4.0),
            contentContainerView.bottomAnchor.constraint(equalTo: bottomNavView.topAnchor),
            bottomNavView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomNavView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomNavView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomNavHeight
        ])

        bottomNavView.isHidden = true
    }

    private func setBottomNavigation(visible: Bool, selected: DavizinBottomNavView.Item = .modes) {
        bottomNavView.isHidden = !visible
        bottomNavView.setSelected(selected)
        let navigationHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 78.0 : 68.0
        bottomNavHeightConstraint?.constant = visible ? navigationHeight : 0.0
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    private func showLogin(animated: Bool) {
        currentStage = .login
        animatedBackgroundView.stopAnimating()
        animatedBackgroundView.isHidden = true
        setBottomNavigation(visible: false)
        headerView.title = "Nyxel External"
        headerView.showsBackButton = false
        headerView.showsAvatarButton = false

        let screen = LoginView()
        screen.delegate = self
        loginView = screen
        display(screen, animated: animated)

        // Chequeo inteligente de compatibilidad del dispositivo
        runCompatibilityCheck()
    }

    /// Prueba si el dispositivo puede inyectar y pinta el estado en el login.
	private func runCompatibilityCheck() {
		guard NyxelSupportPolicy.isCurrentSystemSupported else {
			headerView.setSystemCompatibility(
				"iOS/iPadOS \(NyxelSupportPolicy.currentSystemDescription) • No compatible",
				color: AppTheme.failure
			)
			loginView?.setCompatibility(
				"❌ No compatible: \(NyxelSupportPolicy.currentSystemDescription) no está verificado",
				color: AppTheme.failure
			)
			return
		}

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let result = InjectorService.checkCompatibility()
			DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
				case .compatible:
					self.headerView.setSystemCompatibility(
						"iOS/iPadOS \(NyxelSupportPolicy.currentSystemDescription) • Compatible",
						color: AppTheme.success
					)
					self.loginView?.setCompatibility(
						"✅ Compatible — \(NyxelSupportPolicy.currentSystemDescription)",
						color: AppTheme.success
					)
				case .notCompatible:
					self.headerView.setSystemCompatibility(
						"iOS/iPadOS \(NyxelSupportPolicy.currentSystemDescription) • Sin acceso",
						color: AppTheme.failure
					)
					self.loginView?.setCompatibility(
						"❌ No se pudo acceder al contenedor en \(NyxelSupportPolicy.currentSystemDescription)",
						color: AppTheme.failure
					)
				case .noGameInstalled:
					self.headerView.setSystemCompatibility(
						"iOS/iPadOS \(NyxelSupportPolicy.currentSystemDescription) • Verificado",
						color: AppTheme.accentWarm
					)
					self.loginView?.setCompatibility("⚠️ Instala Free Fire para verificar", color: AppTheme.accentWarm)
				case .unsupportedSystem:
					self.headerView.setSystemCompatibility(
						"iOS/iPadOS \(NyxelSupportPolicy.currentSystemDescription) • No compatible",
						color: AppTheme.failure
					)
					self.loginView?.setCompatibility(
						"❌ No compatible — \(NyxelSupportPolicy.currentSystemDescription) no está verificado",
						color: AppTheme.failure
					)
				}
            }
        }
    }

    private func showGameSelection(animated: Bool) {
        currentStage = .gameSelection
        animatedBackgroundView.isHidden = false
        animatedBackgroundView.startAnimating()
        setBottomNavigation(visible: true, selected: .modes)
		headerView.title = "Seleccionar entorno"
		headerView.showsBackButton = true
		headerView.showsAvatarButton = false

        let screen = GameSelectionView()
        screen.delegate = self
        screen.setSelectedGame(selectedGame)
        gameSelectionView = screen
        display(screen, animated: animated)
    }

    private func showModeSelection(animated: Bool) {
        currentStage = .modeSelection
        setBottomNavigation(visible: true, selected: .modes)
        if let firstActive = DavizinModeCatalog.enabledModes(for: selectedGame).first, selectedMode == nil || !DavizinModeCatalog.enabledModes(for: selectedGame).contains(selectedMode!) {
            selectedMode = firstActive
        }
		headerView.title = "Configurar / \(selectedGame.rawValue)"
		headerView.showsBackButton = true
		headerView.showsAvatarButton = false

        let screen = MissionMapView()
        screen.delegate = self
        screen.setModes(DavizinModeCatalog.enabledModes(for: selectedGame), selected: selectedMode)
        missionMapView = screen
        display(screen, animated: animated)
    }

    private func showOperation(animated: Bool) {
        setBottomNavigation(visible: true, selected: .modes)
        guard let selectedMode, DavizinModeCatalog.enabledModes(for: selectedGame).contains(selectedMode) else {
            showModeSelection(animated: animated)
            return
        }
        currentStage = .operation
		headerView.title = "Control / \(selectedMode.displayName)"
		headerView.showsBackButton = true
		headerView.showsAvatarButton = false

        let screen = OperationView()
        screen.delegate = self
        screen.selectedGame = selectedGame
        screen.selectedMode = selectedMode
        let gameReady = NyxelInstalledGames.statusText().contains(selectedGame == .freeFireMax ? "✓ MAX instalado" : "✓ Free Fire instalado")
        screen.setPreflight([
            activeKey != nil && activeRemainingSeconds > 0 ? "✓ Key autorizada" : "✕ Sesión no autorizada",
            activeRemainingSeconds > 0 ? "✓ Sesión activa" : "✕ Sesión expirada",
            "✓ Modo remoto: \(selectedMode.displayName)",
            gameReady ? "✓ Juego detectado" : "! Juego no detectado"
        ])
        let gameToOpen = selectedGame
        screen.onOpenGame = { [weak self] in
            self?.openGame(gameToOpen)
        }
        operationView = screen
        display(screen, animated: animated)
        if NyxelCleanupFlow.hasPendingWork {
            screen.applyCleanupStage(NyxelCleanupFlow.stage)
        }
    }

    private func showVPN(animated: Bool) {
        stageBeforeProfile = currentStage == .profile ? stageBeforeProfile : currentStage
        currentStage = .profile
        setBottomNavigation(visible: true, selected: .vpn)
        headerView.title = "VPN"
        headerView.showsBackButton = true
        headerView.showsAvatarButton = false
        display(NyxelVPNView(), animated: animated)
    }

    /// Perfil: accesible desde el avatar del header en cualquier pantalla (excepto login).
    private func showProfile(animated: Bool) {
        stageBeforeProfile = currentStage == .profile ? stageBeforeProfile : currentStage
		currentStage = .profile
		setBottomNavigation(visible: true, selected: .profile)
		headerView.title = "Perfil de cuenta"
		headerView.showsBackButton = true
		headerView.showsAvatarButton = false

        let screen = ProfileView()
        screen.delegate = self
        screen.setAccount(key: activeKey, remainingSeconds: activeRemainingSeconds, countryCode: activeCountryCode)
        screen.onAppearanceChanged = { [weak self] in
            self?.overrideUserInterfaceStyle = NyxelAppearanceStore.uiStyle
            self?.showProfile(animated: true)
        }
        screen.onRefreshRequested = { [weak self, weak screen] in
            guard let self, let key = self.activeKey, !key.isEmpty else { return }
            KeyValidator.validate(key: key) { [weak self, weak screen] success, message, remaining, _ in
                guard let self else { return }
                if success && remaining > 0 {
                    NyxelActivityLog.record("Datos del Worker actualizados")
                    self.setAccountSession(key: key, remainingSeconds: remaining, countryCode: KeyValidator.lastCountryCode)
                    screen?.setAccount(key: key, remainingSeconds: remaining, countryCode: KeyValidator.lastCountryCode)
                    DavizinToastCenter.shared.show(title: "Datos actualizados", subtitle: "La key y el Worker están sincronizados.", kind: .success)
                } else {
                    DavizinToastCenter.shared.show(title: "No se pudo actualizar", subtitle: message, kind: .danger)
                }
            }
        }
        screen.refresh()
        profileView = screen
        display(screen, animated: animated)
    }

	/// Abre Free Fire (MAX o normal) usando su esquema de URL.
	private func openGame(_ game: DavizinGame) {
		let beginOpening = { [weak self] in
			DispatchQueue.main.async { self?.performOpenGame(game) }
		}
		if NyxelCleanupFlow.stage == .readyToOpen {
			NyxelCleanupFlow.requestReminderPermission { [weak self] allowed in
					guard !allowed else { beginOpening(); return }
					DispatchQueue.main.async {
						self?.showNotice("Activa las notificaciones de Nyxel si quieres recibir el recordatorio. Si no, vuelve manualmente después de 5 segundos y pulsa LIMPIAR SESIÓN SÍ O SÍ.") {
							beginOpening()
						}
					}
			}
		} else {
			beginOpening()
		}
	}

	private func performOpenGame(_ game: DavizinGame) {
		operationView?.setOpeningGame(true)
		let urls: [URL]
		switch game {
		case .freeFireMax:
			urls = ["freefiremax://", "freefire://"].compactMap(URL.init(string:))
		case .freeFire:
			urls = ["freefireth://", "freefire://"].compactMap(URL.init(string:))
		}

			func showOpenError() {
				NyxelActivityLog.record("No se pudo abrir \(game.rawValue)")
				self.operationView?.showGameOpenResult(success: false)
			let alert = UIAlertController(
				title: "No se pudo abrir el juego",
				message: "No se encontró el esquema de \(game.rawValue). Verifica que el juego esté instalado y prueba de nuevo.",
				preferredStyle: .alert
			)
			alert.addAction(UIAlertAction(title: "Entendido", style: .default))
			present(alert, animated: true)
		}

		func attemptOpen(at index: Int) {
			guard index < urls.count else {
				showOpenError()
				return
			}

				UIApplication.shared.open(urls[index], options: [:]) { success in
					if success {
						let completingCycle = NyxelCleanupFlow.stage == .readyToReopen
						NyxelCleanupFlow.markGameOpened()
						NyxelActivityLog.record("\(game.rawValue) abierto")
						DispatchQueue.main.async {
							if completingCycle {
								if self.activeKey != nil && self.activeRemainingSeconds > 0 {
									self.showOperation(animated: false)
								} else {
									self.showLogin(animated: true)
								}
							} else {
								self.operationView?.showGameOpenResult(success: true)
								self.operationView?.applyCleanupStage(NyxelCleanupFlow.stage)
							}
						}
						return
					}
					DispatchQueue.main.async {
						attemptOpen(at: index + 1)
				}
			}
		}

		// Se intenta directamente: canOpenURL puede devolver false por restricciones
		// de consulta aun cuando el esquema pueda abrirse correctamente.
		attemptOpen(at: 0)
	}

    private func display(_ screen: UIView, animated: Bool) {
        contentContainerView.subviews.forEach { $0.removeFromSuperview() }
        screen.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(screen)
        screen.davizinPinEdges(to: contentContainerView)

        guard animated else {
            screen.alpha = 1.0
            screen.transform = .identity
            return
        }

        screen.alpha = 0.0
        screen.transform = CGAffineTransform(translationX: 0.0, y: 10.0).scaledBy(x: 0.985, y: 0.985)
        UIView.animate(
            withDuration: 0.28,
            delay: 0.0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            screen.alpha = 1.0
            screen.transform = .identity
        }
    }

    private func simulateLogin(key: String) {
        guard let screen = loginView else { return }
        screen.setChecking(true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            guard let self = self, self.currentStage == .login else { return }
            screen.setChecking(false)
            screen.setStatus("Access granted", success: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, self.currentStage == .login else { return }
                screen.playExitAnimation {
                    guard self.currentStage == .login else { return }
                    self.showGameSelection(animated: true)
                }
            }
        }
    }

    private func simulateOperation(_ operation: DavizinOperationKind) {
        guard let screen = operationView else { return }
        let state: DavizinOperationState
        switch operation {
        case .runExploit:
            state = .running
        case .inject:
            state = .injecting
        case .clean:
            state = .cleaning
        }
        screen.setState(state)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { [weak self] in
            guard let self = self, self.currentStage == .operation else { return }
            let message: String
            switch operation {
            case .runExploit:
                message = "Run complete"
            case .inject:
                message = "Configuración inyectada (simulación)"
            case .clean:
                message = "Successfully cleaned !"
            }
            screen.setState(.succeeded(message))
        }
    }

    private func goBack() {
        switch currentStage {
        case .login:
            break
        case .home:
            break
        case .gameSelection:
            showLogin(animated: true)
        case .modeSelection:
            showGameSelection(animated: true)
        case .operation:
            showModeSelection(animated: true)
        case .profile:
            switch stageBeforeProfile {
            case .operation: showOperation(animated: true)
            case .modeSelection: showModeSelection(animated: true)
            case .gameSelection: showGameSelection(animated: true)
            case .home: showGameSelection(animated: true)
            default: showModeSelection(animated: true)
            }
        }
    }
}

extension ViewController: DavizinHeaderViewDelegate {
    func headerViewDidTapBack(_ headerView: DavizinHeaderView) {
        goBack()
    }

    func headerViewDidTapClose(_ headerView: DavizinHeaderView) {
        // La X regresa directo a la pantalla de la key (login)
        showLogin(animated: true)
    }

    func headerViewDidTapAvatar(_ headerView: DavizinHeaderView) {
        guard currentStage != .login, currentStage != .profile else { return }
        showProfile(animated: true)
    }

    func headerViewDidLongPressAvatar(_ headerView: DavizinHeaderView) {
        guard currentStage != .login else { return }
        let alert = UIAlertController(
            title: "¿Cerrar sesión?",
            message: "Vas a regresar a la pantalla de la key.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Cerrar sesión", style: .destructive) { [weak self] _ in
            self?.showLogin(animated: true)
        })
        present(alert, animated: true)
    }
}

extension ViewController: ProfileViewDelegate {
    func profileViewDidTapLogout(_ view: ProfileView) {
        setAccountSession(key: nil, remainingSeconds: 0)
        showLogin(animated: true)
    }
}

extension ViewController: LoginViewDelegate {
    func loginView(_ loginView: LoginView, didTapContinueWithKey key: String) {
        onLoginContinue?(key)
        guard simulateUIStates else { return }
        simulateLogin(key: key)
    }
}

extension ViewController: GameSelectionViewDelegate {
    func gameSelectionView(_ view: GameSelectionView, didSelect game: DavizinGame) {
        selectedGame = game
        NyxelActivityLog.record("Juego seleccionado: \(game.rawValue)")
        onGameSelected?(game)
        showModeSelection(animated: true)
    }
}

extension ViewController: MissionMapViewDelegate {
    func missionMapView(_ view: MissionMapView, didSelect mode: DavizinMode) {
        selectedMode = mode
        NyxelActivityLog.record("Modo seleccionado: \(mode.displayName)")
        onModeSelected?(mode)
        showOperation(animated: true)
    }

    func missionMapViewDidRequestRefresh(_ view: MissionMapView) {
        guard let key = activeKey, !key.isEmpty else {
            view.setSyncState("Sin key activa", syncing: false)
            return
        }
        view.setSyncState("Sincronizando con el Worker…", syncing: true)
        KeyValidator.validate(key: key) { [weak self, weak view] success, message, remaining, _ in
            guard let self else { return }
            if success && remaining > 0 {
                self.setAccountSession(key: key, remainingSeconds: remaining, countryCode: KeyValidator.lastCountryCode)
                NyxelActivityLog.record("Configuración remota sincronizada")
                DispatchQueue.main.async {
                    view?.setSyncState("Configuración sincronizada", syncing: false)
                    self.showModeSelection(animated: false)
                }
            } else {
                NyxelRemoteConfigStore.recordFailure(message)
                view?.setSyncState("No se pudo sincronizar: \(message)", syncing: false)
            }
        }
    }
}

extension ViewController: OperationViewDelegate {
    func operationView(_ view: OperationView, didTap operation: DavizinOperationKind) {
        onOperation?(operation)
        guard simulateUIStates else { return }
        simulateOperation(operation)
    }
}
