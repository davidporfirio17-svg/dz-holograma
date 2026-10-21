import UIKit
import LocalAuthentication

/// Conecta el UI de DavizinxIOS con la logica real de Davizin
final class DavizinBridge {

    private weak var vc: ViewController?
    private var countdownTimer: Timer?
    private var remainingSeconds: Int = 0
    private var injectionProgressObserver: NSObjectProtocol?

    /// Modo elegido por el usuario. Define que cache_res se inyecta.
    private var selectedMode: DavizinMode?

    /// Juego elegido. Define bundle ID y de que slots se descarga.
    private var selectedGame: DavizinGame = .freeFireMax

    /// Credenciales de la sesion actual. Se usan para descargar el cache_res del Worker.
    private var sessionKey: String = ""
    private var sessionHWID: String = ""
    private var operationInFlight = false

    func connect(to viewController: ViewController) {
        self.vc = viewController
        if let injectionProgressObserver {
            NotificationCenter.default.removeObserver(injectionProgressObserver)
        }
        injectionProgressObserver = NotificationCenter.default.addObserver(
            forName: .nyxelInjectionProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let message = notification.object as? String else { return }
            self?.vc?.setOperationProgress(message)
        }
        // Restaurar el ultimo juego y modo elegidos
        if let g = UserDefaults.standard.string(forKey: "dz_last_game"), let game = DavizinGame(rawValue: g) {
            selectedGame = game
        }
        if let m = UserDefaults.standard.string(forKey: "dz_last_mode"), let mode = DavizinModeCatalog.mode(id: m) {
            selectedMode = mode
        }
        viewController.simulateUIStates = false

        // Login: validar key con Cloudflare
        viewController.onLoginContinue = { [weak self] key in
            self?.handleLogin(key: key)
        }

        // Game selection: el usuario elige y avanza
        viewController.onGameSelected = { [weak self] game in
            self?.selectedGame = game
            UserDefaults.standard.set(game.rawValue, forKey: "dz_last_game")
            self?.vc?.showModeSelectionScreen()
        }

        // Mode selection: guardamos el modo y avanzamos
        viewController.onModeSelected = { [weak self] mode in
            self?.selectedMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: "dz_last_mode")
            self?.vc?.showOperationScreen()
        }

        // Operaciones reales
        viewController.onOperation = { [weak self] operation in
            self?.handleOperation(operation)
        }

        viewController.onKexploitExploit = { [weak self] in
            self?.handleKexploitFromTab()
        }

        viewController.onKexploitInject = { [weak self] game, mode in
            self?.handleKexploitInject(game: game, mode: mode)
        }

        viewController.onKexploitOpenGame = { [weak self] game in
            self?.vc?.openGameFromKexploit(game)
        }

        viewController.onClose = {
            // Nada - no cerramos
        }
    }

    // MARK: - Login

    private func handleLogin(key: String) {
        vc?.setLoginChecking(true)

        let upperKey = key.uppercased()
        NSLog("[DavizinBridge] handleLogin iniciado — build=%@", KeyValidator.getAppBuild())

        KeyValidator.validate(key: upperKey) { [weak self] success, message, remaining, notice in
            NSLog("[DavizinBridge] Resultado: success=%d, remaining=%d, msg=%@",
                  success ? 1 : 0, remaining, message ?? "(nil)")
            self?.vc?.setLoginChecking(false)

            if success && remaining > 0 {
                NyxelActivityLog.record("Key validada")
                self?.vc?.setLoginStatus("Acceso concedido ✓", success: true)
                self?.remainingSeconds = remaining
                self?.vc?.setAccountSession(key: upperKey, remainingSeconds: remaining, countryCode: KeyValidator.lastCountryCode)

                self?.sessionKey = upperKey
                self?.sessionHWID = KeyValidator.getDeviceHWID()

                // Entrelazado anti-crack: deriva el fingerprint de la Key y lo
                // deja en memoria. Varios puntos del flujo lo re-chequean antes
                // de inyectar. Si alguien parchea `success` para forzar login
                // sin pasar por `KeyValidator.validate`, aquí nadie llama a
                // bind() y el fingerprint queda nil → la inyección degrada.
                NyxelAuthorizationState.shared.bind(
                    key: upperKey,
                    hwid: KeyValidator.getDeviceHWID()
                )

                self?.startCountdown()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let notice = notice, !notice.isEmpty {
                        self?.vc?.showNotice(notice) {
                            self?.continueAfterLogin()
                        }
                    } else {
                        self?.continueAfterLogin()
                    }
                }
            } else {
                if KeyValidator.lastValidationWasVersionUnavailable {
                    NSLog("[DavizinBridge] Build %@ rechazado por el Worker — actualizar allowed_app_builds", KeyValidator.getAppBuild())
                    self?.vc?.setLoginStatus("Versión no disponible", success: false)
                    self?.showVersionUnavailableAlert()
                } else {
                    self?.vc?.setLoginStatus(message ?? "Key invalida", success: false)
                }
            }
        }
    }

    private func continueAfterLogin() {
        if NyxelCleanupFlow.hasPendingWork, let game = NyxelCleanupFlow.game {
            selectedGame = game
            let savedModeID = UserDefaults.standard.string(forKey: "dz_last_mode")
            let mode = selectedMode ?? savedModeID.flatMap { DavizinModeCatalog.mode(id: $0) }
            vc?.showCleanupRecoveryScreen(for: game, mode: mode)
        } else {
            vc?.showGameSelectionScreen()
        }
    }

    // MARK: - Operaciones

    /// External usa Remote Pairing/RSD/AirLift como ruta primaria en iOS 27.
    /// Tener un registro guardado no es una elevación de privilegios: solo indica
    /// que el canal soportado para operaciones de archivos puede intentarse.
    private static var airLiftRouteAvailable: Bool {
        NixelAirLiftFileChannel.isAvailable
    }

    private func performInjection(game: DavizinGame, mode: DavizinMode, key: String, hwid: String) {
        // Chequeo distribuido 1/N (entrada): la Key en memoria debe seguir siendo
        // coherente con el fingerprint derivado al login. Si el fingerprint no
        // cuadra o nunca se bindeó, degradamos como "éxito falso" — el atacante
        // ve "Operación completada" en pantalla pero no se escribió nada.
        guard NyxelRuntimeState.shared.isTrustedForCriticalOperation() else {
            NyxelActivityLog.record("NYX-TRUST failed at entry")
            DispatchQueue.main.async { [weak self] in
                self?.operationInFlight = false
                // Degradación silenciosa: mensaje de éxito sin ejecutar nada real.
                self?.vc?.setOperationState(.succeeded("Operación completada"))
            }
            return
        }

        // iOS 17–26 → kexploit directo. Sin VPN, sin pairing.
        // iOS 27+   → AirLift + VPN loopback.
        let iosVersion = NyxelDeviceInfo.versionTuple
        let useKexploitPath = NyxelSupportPolicy.supportsKernelOffsets(
            major: iosVersion.major,
            minor: iosVersion.minor
        )

        // El preflight de Modo Avión solo aplica al camino AirLift.
        if !useKexploitPath {
            let netState = NyxelCellularPreflight.currentState()
            if netState == .cellularOnly {
                NyxelActivityLog.record("Preflight: solo datos celulares detectado — pidiendo Modo Avión al usuario")
                DispatchQueue.main.async { [weak self] in
                    guard let self, let vc = self.vc else { return }
                    NyxelCellularPreflight.presentAirplaneModeGuide(
                        from: vc,
                        onContinue: { [weak self] in
                            self?.performInjection(game: game, mode: mode, key: key, hwid: hwid)
                        },
                        onCancel: { [weak self] in
                            self?.operationInFlight = false
                            self?.vc?.setOperationState(.failed("Operación cancelada: activa Modo Avión para operar con datos."))
                        }
                    )
                }
                return
            }
        }
        vc?.setOperationState(.injecting)
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        NyxelActivityLog.record("========== INJECTION TRACE BEGIN ==========")
        NyxelActivityLog.record("DIAG appVersion=\(appVersion) system=\(NyxelSupportPolicy.currentSystemDescription) game=\(game.rawValue) mode=\(mode.displayName) pairingRecordAvailable=\(Self.airLiftRouteAvailable)")

        // Los modos marcados como "hybrid" en la configuración remota usan el
        // Packet Tunnel local antes de descargar/aplicar el recurso. Los modos
        // normales conservan exactamente el flujo anterior.
        let wantsHybrid = mode.accessTier.lowercased() == "hybrid"
            || mode.id.lowercased().contains("hybrid")
            || mode.label.lowercased().contains("hybrid")

        guard useKexploitPath || Self.airLiftRouteAvailable else {
            let message = "iOS \(iosVersion.major).\(iosVersion.minor) requiere pairing AirLift. Agrega el pairing desde Ajustes."
            NyxelActivityLog.record(message)
            DispatchQueue.main.async {
                self.operationInFlight = false
                self.vc?.setOperationState(.failed(message))
            }
            return
        }

        let injectNow: () -> Void = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                // Prioridad por versión: en iOS ≤26.0.x usamos kexploit aunque haya
                // un pairing AirLift guardado — es el camino verificado para esos
                // builds y no requiere VPN. AirLift queda para iOS 26.1+ y 27+.
                if useKexploitPath {
                    NyxelActivityLog.record("iOS \(iosVersion.major).\(iosVersion.minor): usando kexploit (ruta verificada para este build)")
                    if sandbox_access_is_active() == 0 {
                        NyxelActivityLog.record("Sandbox no activo, ejecutando exploit antes de inyectar...")
                        let exploitResult = kexploit_opa334()
                        guard exploitResult == 0 else {
                            let code = abs(exploitResult)
                            let message = "KXP-\(code) — \(Self.kxpDetail(code))"
                            NyxelActivityLog.record("Exploit pre-inyección falló (\(message))")
                            DispatchQueue.main.async {
                                self.operationInFlight = false
                                self.vc?.setOperationState(.failed(message))
                            }
                            return
                        }

                        let selfProc = proc_self()
                        let escapeResult = sandbox_escape(selfProc)
                        let sandboxActive = sandbox_access_is_active() != 0
                        NyxelActivityLog.record("Exploit pre-inyección: sandbox_escape=\(escapeResult), activo=\(sandboxActive)")
                        guard escapeResult == 0 && sandboxActive else {
                            let message = "SBX-001 — El exploit terminó, pero el sandbox escape no quedó activo (\(escapeResult))."
                            DispatchQueue.main.async {
                                self.operationInFlight = false
                                self.vc?.setOperationState(.failed(message))
                            }
                            return
                        }
                    }
                } else if Self.airLiftRouteAvailable {
                    NyxelActivityLog.record("AirLift disponible: usando Remote Pairing/RSD para la escritura")
                }

                // Chequeo distribuido 2/N (justo antes del write real): si el
                // fingerprint se perdió entre el entry y acá, o si asomaron Frida
                // u otro hook en caliente, no inyectamos. Reportamos éxito falso.
                guard NyxelRuntimeState.shared.isTrustedForCriticalOperation() else {
                    NyxelActivityLog.record("NYX-TRUST failed at pre-write")
                    DispatchQueue.main.async {
                        self.operationInFlight = false
                        self.vc?.setOperationState(.succeeded("Operación completada"))
                    }
                    return
                }
                let result = InjectorService.inject(game: game, mode: mode, key: key, hwid: hwid)
                if result.success && mode.oneTime {
                    self.consumeOneTimeMode(mode: mode, key: key, hwid: hwid, result: result)
                } else {
                    DispatchQueue.main.async {
                        self.hapticFeedback(success: result.success)
                        self.operationInFlight = false
                        self.vc?.setOperationState(result.success ? .succeeded(result.message) : .failed(result.message))
                    }
                }
            }
        }

        // iOS ≤26.0.x NUNCA requiere el loopback RSD aunque el modo sea "hybrid"
        // ni aunque exista un pairing AirLift guardado — kexploit es autosuficiente.
        let requiresRSDLoopback = !useKexploitPath && (wantsHybrid || Self.airLiftRouteAvailable)
        guard requiresRSDLoopback else {
            injectNow()
            return
        }

        NixelHybridCoordinator.startForAirLift { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                NyxelActivityLog.record("Hybrid VPN verificado; ruta TCP RSD alcanzable")
                injectNow()
            case .failure(let error):
                let message = "Inyección detenida: el loopback VPN/RSD no está listo. \(error.localizedDescription)"
                NyxelActivityLog.record(message)
                DispatchQueue.main.async {
                    self.hapticFeedback(success: false)
                    self.operationInFlight = false
                    self.vc?.setOperationState(.failed(message))
                }
            }
        }
    }

    private func consumeOneTimeMode(mode: DavizinMode, key: String, hwid: String, result: InjectorResult) {
        guard let url = URL(string: "https://dz-holograma.davidporfirio17.workers.dev/consume-mode") else {
            operationInFlight = false
            vc?.setOperationState(.failed("NYX-002 — No se pudo confirmar la operación con el Worker."))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        KeyValidator.applySecurityHeaders(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key, "hwid": hwid, "mode": mode.id])
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && ((try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["success"] as? Bool == true)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hapticFeedback(success: ok)
                if ok { DavizinModeCatalog.markConsumed(mode.id) }
                self.operationInFlight = false
                self.vc?.setOperationState(ok ? .succeeded(result.message) : .failed("La inyección se realizó, pero no se pudo confirmar el consumo del modo. No vuelvas a intentarlo hasta revisar la conexión."))
            }
        }.resume()
    }

    private func handleKexploitFromTab() {
        guard !operationInFlight else {
            vc?.setKexploitState(.failed("NYX-006 — Ya hay una operación en curso."))
            return
        }
        operationInFlight = true
        vc?.setKexploitState(.running)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if sandbox_access_is_active() != 0 {
                NyxelActivityLog.record("Sandbox ya activo, exploit innecesario")
                DispatchQueue.main.async {
                    self.operationInFlight = false
                    self.vc?.setKexploitState(.sandboxActive)
                }
                return
            }

            NyxelActivityLog.record("Iniciando kexploit_opa334...")
            let exploitResult = kexploit_opa334()
            guard exploitResult == 0 else {
                let code = abs(exploitResult)
                let detail = Self.kxpDetail(code)
                NyxelActivityLog.record("kexploit_opa334 falló: code \(code) — \(detail)")
                DispatchQueue.main.async {
                    self.operationInFlight = false
                    self.vc?.setKexploitState(.failed("KXP-\(code) — \(detail)"))
                }
                return
            }

            NyxelActivityLog.record("kexploit exitoso, ejecutando sandbox_escape...")
            let selfProc = proc_self()
            let escapeResult = sandbox_escape(selfProc)
            let active = sandbox_access_is_active() != 0
            NyxelActivityLog.record("sandbox_escape return=\(escapeResult), activo: \(active)")

            DispatchQueue.main.async {
                self.operationInFlight = false
                self.hapticFeedback(success: active)
                if active {
                    self.vc?.setKexploitState(.sandboxActive)
                } else {
                    self.vc?.setKexploitState(.failed("SBX-001 — Sandbox escape no verificado."))
                }
            }
        }
    }

    private func handleKexploitInject(game: DavizinGame, mode: DavizinMode) {
        guard !operationInFlight else {
            vc?.setKexploitState(.failed("NYX-006 — Ya hay una operación en curso."))
            return
        }
        guard !sessionKey.isEmpty else {
            vc?.setKexploitState(.failed("NYX-001 — Sesión no autorizada."))
            return
        }
        operationInFlight = true
        vc?.setKexploitState(.injecting)

        let key = sessionKey
        let hwid = sessionHWID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if sandbox_access_is_active() == 0 {
                NyxelActivityLog.record("Sandbox no activo, ejecutando exploit antes de inyectar...")
                let exploitResult = kexploit_opa334()
                guard exploitResult == 0 else {
                    let code = abs(exploitResult)
                    let message = "KXP-\(code) — \(Self.kxpDetail(code))"
                    NyxelActivityLog.record("Exploit pre-inyección falló (\(message))")
                    DispatchQueue.main.async {
                        self.operationInFlight = false
                        self.vc?.setKexploitState(.failed(message))
                    }
                    return
                }

                let selfProc = proc_self()
                let escapeResult = sandbox_escape(selfProc)
                let sandboxActive = sandbox_access_is_active() != 0
                NyxelActivityLog.record("Exploit pre-inyección: sandbox_escape=\(escapeResult), activo=\(sandboxActive)")
                guard escapeResult == 0 && sandboxActive else {
                    let message = "SBX-001 — El exploit terminó, pero el sandbox escape no quedó activo (\(escapeResult))."
                    DispatchQueue.main.async {
                        self.operationInFlight = false
                        self.vc?.setKexploitState(.failed(message))
                    }
                    return
                }
            }

            guard NyxelRuntimeState.shared.isTrustedForCriticalOperation() else {
                NyxelActivityLog.record("NYX-TRUST failed at pre-write")
                DispatchQueue.main.async {
                    self.operationInFlight = false
                    self.vc?.setKexploitState(.injected("Operación completada"))
                }
                return
            }

            let result = InjectorService.inject(game: game, mode: mode, key: key, hwid: hwid)
            DispatchQueue.main.async {
                self.hapticFeedback(success: result.success)
                self.operationInFlight = false
                if result.success {
                    NyxelCleanupFlow.markInjectionSucceeded(for: game)
                    self.vc?.setKexploitState(.injected(result.message))
                } else {
                    self.vc?.setKexploitState(.failed(result.message))
                }
            }
        }
    }

    private func handleOperation(_ operation: DavizinOperationKind) {
        guard !operationInFlight else {
            vc?.setOperationState(.failed("NYX-006 — Ya hay una operación en curso."))
            return
        }
        if operation == .clean {
            operationInFlight = true
            executeAuthorizedOperation(.clean)
            return
        }
        guard !sessionKey.isEmpty else {
            vc?.setOperationState(.failed("NYX-001 — Sesión no autorizada."))
            return
        }

        operationInFlight = true
        vc?.setOperationState(.checking)
        let key = sessionKey
        KeyValidator.validate(key: key) { [weak self] success, message, remaining, _ in
            guard let self else { return }
            guard success && remaining > 0 else {
                self.operationInFlight = false
                NyxelActivityLog.record("Operación bloqueada: key no autorizada")
                self.vc?.setOperationState(.failed("NYX-001 — La key ya no está autorizada por el Worker."))
                return
            }
            self.remainingSeconds = remaining
            self.vc?.setAccountSession(key: key, remainingSeconds: remaining)
            self.executeAuthorizedOperation(operation)
        }
    }

    private func executeAuthorizedOperation(_ operation: DavizinOperationKind) {
        switch operation {

        case .runExploit:
            vc?.setOperationState(.running)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }

                // iOS 17–26 → kexploit; iOS 27+ → AirLift.
                let version = NyxelDeviceInfo.versionTuple
                let useKexploitPath = NyxelSupportPolicy.supportsKernelOffsets(
                    major: version.major,
                    minor: version.minor
                )

                if !useKexploitPath && Self.airLiftRouteAvailable {
                    NyxelActivityLog.record("Remote Pairing guardado: se usará el túnel RSD/AirLift real")
                    DispatchQueue.main.async {
                        self.operationInFlight = false
                        self.vc?.setOperationState(.succeeded("Remote Pairing guardado ✓ — AirLift se validará al escribir"))
                    }
                    return
                }

                if !useKexploitPath {
                    let message = "iOS \(version.major).\(version.minor) requiere pairing AirLift. Agrega el pairing desde Ajustes."
                    NyxelActivityLog.record(message)
                    DispatchQueue.main.async {
                        self.operationInFlight = false
                        self.vc?.setOperationState(.failed(message))
                    }
                    return
                }

                if sandbox_access_is_active() != 0 {
                    NyxelActivityLog.record("Sandbox ya activo, exploit innecesario")
                    DispatchQueue.main.async {
                        self.operationInFlight = false
                        self.vc?.setOperationState(.succeeded("Sandbox ya activo ✓"))
                    }
                    return
                }

                NyxelActivityLog.record("Iniciando kexploit_opa334...")
                let exploitResult = kexploit_opa334()
                guard exploitResult == 0 else {
                    let code = abs(exploitResult)
                    let detail = Self.kxpDetail(code)
                    NyxelActivityLog.record("kexploit_opa334 falló: code \(code) — \(detail)")
                    DispatchQueue.main.async {
                        self.operationInFlight = false
                        self.vc?.setOperationState(.failed("KXP-\(code) — \(detail)"))
                    }
                    return
                }

                NyxelActivityLog.record("kexploit exitoso, ejecutando sandbox_escape...")
                let selfProc = proc_self()
                let escapeResult = sandbox_escape(selfProc)
                let active = sandbox_access_is_active() != 0
                NyxelActivityLog.record("sandbox_escape return=\(escapeResult), activo: \(active)")

                DispatchQueue.main.async {
                    self.operationInFlight = false
                    self.hapticFeedback(success: active)
                    self.vc?.setOperationState(active
                        ? .succeeded("Sistema preparado ✓")
                        : .failed("SBX-001 — Sandbox escape no verificado."))
                }
            }

        case .inject:
            authenticateForInjection { [weak self] allowed in
                guard let self else { return }
                guard allowed else {
                    self.operationInFlight = false
                    self.vc?.setOperationState(.failed("NYX-008 — Autenticación cancelada."))
                    return
                }
                self.startInjectionFlow()
            }

        case .clean:
            vc?.setOperationState(.cleaning)
            let game = selectedGame
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let result = InjectorService.uninject(game: game)
                DispatchQueue.main.async {
                    self.hapticFeedback(success: result.success)
                    self.operationInFlight = false
                    if result.success { NyxelCleanupFlow.markCleaningSucceeded(for: game) }
                    self.vc?.setOperationState(
                        result.success
                            ? .succeeded(result.message)
                            : .failed(result.message)
                    )
                }
            }
        }
    }

    private func authenticateForInjection(completion: @escaping (Bool) -> Void) {
        guard UserDefaults.standard.bool(forKey: "nyxel.biometric.enabled") else {
            completion(true)
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Confirma para ejecutar Inject en Nyxel") { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    private func startInjectionFlow() {
            guard let mode = selectedMode else {
                vc?.setOperationState(.failed("No hay un modo disponible en el Worker."))
                return
            }
            let game = selectedGame
            let key = sessionKey
            let hwid = sessionHWID
            if mode.oneTime && !mode.consumed {
                vc?.showNotice("⚠️ Modo de uso único\n\nUna vez completado correctamente, este modo se consumirá definitivamente para esta key. ¿Deseas continuar?") { [weak self] in
                    self?.vc?.showNotice("🔴 Confirmación final\n\nEsta acción consumirá permanentemente el modo y no se puede deshacer. ¿Confirmas la inyección?") { [weak self] in
                        self?.performInjection(game: game, mode: mode, key: key, hwid: hwid)
                    }
                }
            } else {
                performInjection(game: game, mode: mode, key: key, hwid: hwid)
            }
    }

    private func showVersionUnavailableAlert() {
        let build = KeyValidator.getAppBuild()
        let alert = UIAlertController(
            title: "Versión no disponible",
            message: "Esta versión de la app (build \(build)) no está autorizada por el servidor. Ve a la configuración del Worker → Builds permitidos y agrega el build \(build).",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Entendido", style: .default))
        vc?.present(alert, animated: true)
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownTimer?.invalidate()
        // Pintar de inmediato al arrancar
        vc?.setCountdownText(countdownString())
        vc?.setCountdownColor(countdownColor())
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            }
            // Actualizar el contador visible en el header cada segundo
            self.vc?.setCountdownText(self.countdownString())
            self.vc?.setCountdownColor(self.countdownColor())
            self.vc?.setAccountSession(key: self.sessionKey, remainingSeconds: self.remainingSeconds)
        }
    }

    func countdownString() -> String {
        let d = remainingSeconds / 86400
        let h = (remainingSeconds % 86400) / 3600
        let m = (remainingSeconds % 3600) / 60
        let s = remainingSeconds % 60
        if d > 0 { return String(format: "⏳ %dd %02dh %02dm %02ds", d, h, m, s) }
        return String(format: "⏳ %02d:%02d:%02d", h, m, s)
    }

    /// Color del contador segun el tiempo restante.
    private func countdownColor() -> UIColor {
        if remainingSeconds <= 3600 {          // menos de 1 hora -> rojo
            return AppTheme.failure
        } else if remainingSeconds <= 86400 {  // menos de 1 dia -> amarillo
            return AppTheme.accentWarm
        } else {                                // mas de 1 dia -> verde
            return AppTheme.success
        }
    }

    static func kxpDetail(_ code: Int32) -> String {
        switch code {
        case 2:  return "Versión iOS no soportada"
        case 11: return "IOSurface create falló"
        case 12: return "Memory entry falló"
        case 13: return "VM map falló (phys)"
        case 21: return "VM alloc falló (pe_v1)"
        case 22: return "Memory entry falló (pe_v1)"
        case 23: return "Port dealloc falló (pe_v1)"
        case 24: return "Timeout pe_v1 (race no ganó en 90s)"
        case 31: return "VM alloc falló (pe_v2)"
        case 32: return "VM alloc search falló (pe_v2)"
        case 33: return "Memory entry falló (pe_v2)"
        case 34: return "Timeout pe_v2 (race no ganó en 90s)"
        case 41: return "Socket corrupt getsockopt falló"
        case 51: return "Control setsockopt falló"
        case 52: return "Target setsockopt falló"
        case 53: return "Dirección kernel inválida"
        case 54: return "Lectura excede tamaño"
        case 55: return "Lectura kernel getsockopt falló"
        case 56: return "Escritura kernel setsockopt falló"
        case 61: return "Socket addr no encontrado"
        case 62: return "Kernel base no encontrado (scan agotado)"
        case 81: return "OOB read VM map falló"
        case 82: return "OOB write VM map falló"
        default:
            if code >= 7100 && code < 7200 {
                let kr = code - 7100
                return "Race VM map falló (kr=\(kr))"
            }
            return "No se pudo preparar el entorno"
        }
    }

    /// Vibracion segun resultado: exito (suave) o error (fuerte).
    private func hapticFeedback(success: Bool) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(success ? .success : .error)
    }

}
