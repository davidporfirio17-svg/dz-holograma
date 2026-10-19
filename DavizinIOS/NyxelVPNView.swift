import UIKit
import NetworkExtension

/// Pantalla aislada del apartado VPN. No comparte lógica con Modos, Operación ni la inyección.
final class NyxelVPNView: UIView {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let toggleButton = DavizinButton(title: "Activar VPN", style: .primary)
    private let pairingLabel = UILabel()
    private let pairingLogLabel = UILabel()
    private let pairButton = DavizinButton(title: "Emparejar (publicar 2424)", style: .secondary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let width = min(AppTheme.contentMaximumWidth, 520)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: width),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18)
        ])
        let fill = stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        fill.priority = .defaultHigh
        fill.isActive = true

        let category = UILabel()
        category.text = "VPN"
        category.font = AppTheme.captionFont()
        category.textColor = AppTheme.tertiaryText
        category.textAlignment = .center
        stack.addArrangedSubview(category)

        stack.addArrangedSubview(makeStatusCard())
        stack.addArrangedSubview(makeStepsCard())

        toggleButton.addTarget(self, action: #selector(toggleVPN), for: .touchUpInside)
        toggleButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight).isActive = true
        stack.addArrangedSubview(toggleButton)

        let settingsButton = DavizinButton(title: "Abrir ajustes de VPN", style: .secondary)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        settingsButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight).isActive = true
        stack.addArrangedSubview(settingsButton)

        stack.addArrangedSubview(makePairingCard())

        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus), name: .NEVPNStatusDidChange, object: nil)
        NixelVPNManager.shared.load { [weak self] _ in self?.refreshStatus() }
        refreshStatus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Ojo: NO detener NixelPairingSession aquí. El usuario sale de esta
        // pestaña para ir a inyectar — si apagamos el host de emparejamiento
        // al cambiar de pestaña, el dispositivo pierde la sesión justo antes
        // de necesitarla para abrir el túnel AFC.
    }

    @objc private func refreshStatus() {
        DispatchQueue.main.async {
            let manager = NixelVPNManager.shared
            self.statusLabel.text = NixelVPNManager.statusText(manager.status)
            self.statusLabel.textColor = manager.status == .connected ? AppTheme.success : AppTheme.warm
            self.toggleButton.setTitle(manager.isActive ? "Detener VPN" : "Activar VPN", for: .normal)
        }
    }

    @objc private func toggleVPN() {
        let manager = NixelVPNManager.shared
        if manager.isActive {
            manager.stop()
            return
        }
        statusLabel.text = "Activando…"
        manager.start { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    self?.statusLabel.text = "No se pudo activar: \(error.localizedDescription)"
                    self?.statusLabel.textColor = AppTheme.failure
                } else {
                    self?.refreshStatus()
                }
            }
        }
    }

    private func makeStatusCard() -> UIView {
        let card = DavizinCardView()
        let title = UILabel()
        title.text = "Estado"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        statusLabel.text = "Sin configurar"
        statusLabel.font = AppTheme.bodyFont()
        statusLabel.textColor = AppTheme.warm
        statusLabel.numberOfLines = 0

        let note = UILabel()
        note.text = "Este apartado es independiente de Modos y de la inyección."
        note.font = AppTheme.bodyFont()
        note.textColor = AppTheme.secondaryText
        note.numberOfLines = 0

        let inner = UIStackView(arrangedSubviews: [title, statusLabel, note])
        inner.axis = .vertical
        inner.spacing = 8
        card.addContent(inner)
        return card
    }

    private func makeStepsCard() -> UIView {
        let card = DavizinCardView()
        let title = UILabel()
        title.text = "Vinculación"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        let steps = [
            "1. Activar el VPN de Nyxel",
            "2. Ajustes > Privacidad y seguridad > Modo desarrollador",
            "3. Emparejar el dispositivo",
            "4. Introducir el código y volver a la app",
            "5. El dispositivo queda vinculado"
        ]
        var views: [UIView] = [title]
        for text in steps {
            let label = UILabel()
            label.text = text
            label.font = AppTheme.bodyFont()
            label.textColor = AppTheme.secondaryText
            label.numberOfLines = 0
            views.append(label)
        }
        let inner = UIStackView(arrangedSubviews: views)
        inner.axis = .vertical
        inner.spacing = 8
        card.addContent(inner)
        return card
    }

    @objc private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func makePairingCard() -> UIView {
        let card = DavizinCardView()
        let title = UILabel()
        title.text = "Emparejamiento (2424)"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        pairingLabel.text = "Pairing sin iniciar"
        pairingLabel.font = AppTheme.bodyFont()
        pairingLabel.textColor = AppTheme.secondaryText
        pairingLabel.numberOfLines = 0

        pairingLogLabel.font = AppTheme.monoFont(10)
        pairingLogLabel.textColor = AppTheme.tertiaryText
        pairingLogLabel.numberOfLines = 0

        pairButton.addTarget(self, action: #selector(beginPairing), for: .touchUpInside)
        pairButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight).isActive = true

        let pinHint = UILabel()
        pinHint.text = "Después de tocar \"Pair with 2424\" en Ajustes, iOS pide un código. Ese código lo muestra esta app arriba, en el estado — escríbelo en el diálogo de iOS, no aquí."
        pinHint.font = AppTheme.bodyFont()
        pinHint.textColor = AppTheme.secondaryText
        pinHint.numberOfLines = 0

        let inner = UIStackView(arrangedSubviews: [title, pairingLabel, pairButton, pinHint, pairingLogLabel])
        inner.axis = .vertical
        inner.spacing = 10
        card.addContent(inner)
        return card
    }

    @objc private func beginPairing() {
        pairingLogLabel.text = ""
        NixelHybridCoordinator.start { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    self?.pairingLabel.text = "VPN no disponible: \(error.localizedDescription)"
                    self?.pairingLabel.textColor = AppTheme.failure
                    return
                }
                self?.startPairingSession()
            }
        }
    }

    private func startPairingSession() {
        NixelPairingSession.shared.begin { [weak self] state in
            guard let self else { return }
            self.pairingLabel.text = state.message
            switch state {
            case .failed:
                self.pairingLabel.font = AppTheme.bodyFont()
                self.pairingLabel.textColor = AppTheme.failure
            case .ready, .paired:
                self.pairingLabel.font = AppTheme.bodyFont()
                self.pairingLabel.textColor = AppTheme.success
            case .pairingRequired:
                self.pairingLabel.font = AppTheme.titleFont(20)
                self.pairingLabel.textColor = AppTheme.accent
            default:
                self.pairingLabel.font = AppTheme.bodyFont()
                self.pairingLabel.textColor = AppTheme.secondaryText
            }
            let previous = self.pairingLogLabel.text.map { $0 + "\n" } ?? ""
            self.pairingLogLabel.text = (previous + state.message).suffix(2000).description
        }
    }

}
