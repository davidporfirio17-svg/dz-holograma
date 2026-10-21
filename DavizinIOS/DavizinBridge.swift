import UIKit
import LocalAuthentication

/// Conecta el UI de DavizinxIOS con la logica real de Davizin
final class DavizinBridge {

    private weak var vc: ViewController?
    private var countdownTimer: Timer?
    private var remainingSeconds: Int = 0

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

        viewController.onClose = {
            // Nada - no cerramos
        }
    }

    // MARK: - Login

    private func handleLogin(key: String) {
        vc?.setLoginChecking(true)

        let upperKey = key.uppercased()

        KeyValidator.validate(key: upperKey) { [weak self] success, message, remaining, notice in
            self?.vc?.setLoginChecking(false)

            if success && remaining > 0 {
                NyxelActivityLog.record("Key validada")
                self?.vc?.setLoginStatus("Acceso concedido ✓", success: true)
                self?.remainingSeconds = remaining
                self?.vc?.setAccountSession(key: upperKey, remainingSeconds: remaining, countryCode: KeyValidator.lastCountryCode)

                // Guardar credenciales para las descargas de cache_res
                self?.sessionKey = upperKey
                self?.sessionHWID = KeyValidator.getDeviceHWID()

                self?.startCountdown()

                // Los modos ya se guardaron en DavizinModeCatalog dentro de
                // KeyValidator.validate() (lee resp.data.modes del /check real),
                // asi que aqui solo falta mostrar el aviso si hay uno.
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
                self?.vc?.setLoginStatus(message ?? "Key invalida", success: false)
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

    private func performInjection(game: DavizinGame, mode: DavizinMode, key: String, hwid: String) {
        vc?.setOperationState(.injecting)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
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

    private func handleOperation(_ operation: DavizinOperationKind) {
        guard !operationInFlight else {
            vc?.setOperationState(.failed("NYX-006 — Ya hay una operación en curso."))
            return
        }
        if operation == .inject && NyxelCleanupFlow.hasPendingWork {
            vc?.setOperationState(.failed("Limpia sesión sí o sí antes de volver a inyectar."))
            return
        }
        if operation == .clean {
            guard NyxelCleanupFlow.stage == .needsCleaning else {
                vc?.setOperationState(.failed("No hay una limpieza pendiente que pueda confirmarse."))
                return
            }
            if let pendingGame = NyxelCleanupFlow.game { selectedGame = pendingGame }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.operationInFlight = false
                self?.vc?.setOperationState(.succeeded("Sistema listo ✓"))
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

    /// Vibracion segun resultado: exito (suave) o error (fuerte).
    private func hapticFeedback(success: Bool) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(success ? .success : .error)
    }

}
