import UIKit
import NetworkExtension
import UserNotifications

/// Pantalla de conectividad y pairing de iOS 27.
/// Mantiene la lógica existente y reorganiza la información según el tamaño de pantalla.
final class NyxelVPNView: UIView {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let accessStatusLabel = UILabel()
    private let keyValueLabel = UILabel()
    private let remainingValueLabel = UILabel()
    private let statusLabel = UILabel()
    private let statusDot = UIView()
    private let systemLabel = UILabel()
    private let toggleButton = DavizinButton(title: "Conectar", style: .primary)
    private let pairingLabel = UILabel()
    private let pairingDot = UIView()
    private let pairButton = DavizinButton(title: "Iniciar Pairing", style: .secondary)
    private let pairingConnectedBadge = UIStackView()
    private let pairingConnectedIcon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let pairingConnectedText = UILabel()
    private let deviceModelLabel = UILabel()
    private let deviceConnectionLabel = UILabel()
    private let batteryValueLabel = UILabel()
    private let supportStatusLabel = UILabel()
    private let supportedVersionsLabel = UILabel()
    private let supportNoteLabel = UILabel()
    private let batteryNoteLabel = UILabel()
    private let batteryProgressView = UIProgressView(progressViewStyle: .default)
    private var activeKey: String?
    private var accessExpiresAt: Date?
    private var accessTimer: Timer?
    private var batteryRefreshTimer: Timer?
    private var iPadColumns: UIStackView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setAccount(key: String?, remainingSeconds: Int) {
        activeKey = key
        accessExpiresAt = key != nil && remainingSeconds > 0
            ? Date().addingTimeInterval(TimeInterval(remainingSeconds))
            : nil
        updateAccessSummary()
        accessTimer?.invalidate()
        accessTimer = nil
        guard accessExpiresAt != nil else { return }
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateAccessSummary()
        }
    }

    private func configure() {
        backgroundColor = .clear
        UIDevice.current.isBatteryMonitoringEnabled = true
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let horizontalInset: CGFloat = isPad ? 32 : 18
        let width: CGFloat = isPad ? 1040 : min(AppTheme.contentMaximumWidth, 520)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: width),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -horizontalInset)
        ])
        let fill = stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * horizontalInset)
        fill.priority = .defaultHigh
        fill.isActive = true

        let category = UILabel()
        category.text = "NYXEL · ESTADO DEL DISPOSITIVO"
        category.font = AppTheme.captionFont()
        category.textColor = AppTheme.readableAccent
        category.textAlignment = .center
        category.accessibilityTraits = .header
        stack.addArrangedSubview(category)

        let connectionCard = makeConnectionCard()
        let pairingCard = makePairingCard()
        let accessCard = makeAccessCard()
        let deviceCard = makeDeviceCard()
        let supportCard = makeSupportCard()

        if isPad {
            let primaryColumn = UIStackView(arrangedSubviews: [connectionCard, pairingCard])
            primaryColumn.axis = .vertical
            primaryColumn.alignment = .fill
            primaryColumn.spacing = 16

            let detailsColumn = UIStackView(arrangedSubviews: [accessCard, deviceCard, supportCard])
            detailsColumn.axis = .vertical
            detailsColumn.alignment = .fill
            detailsColumn.spacing = 16

            let columns = UIStackView(arrangedSubviews: [primaryColumn, detailsColumn])
            columns.axis = .horizontal
            columns.alignment = .top
            columns.distribution = .fillEqually
            columns.spacing = 16
            iPadColumns = columns
            stack.addArrangedSubview(columns)
        } else {
            [connectionCard, pairingCard, accessCard, deviceCard, supportCard].forEach {
                stack.addArrangedSubview($0)
            }
        }

        toggleButton.addTarget(self, action: #selector(toggleConnection), for: .touchUpInside)
        pairButton.addTarget(self, action: #selector(beginPairing), for: .touchUpInside)

        NotificationCenter.default.addObserver(self, selector: #selector(refreshBattery), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBattery), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus), name: .NEVPNStatusDidChange, object: nil)
        NixelVPNManager.shared.load { [weak self] _ in self?.refreshStatus() }
        refreshSystemStatus()
        refreshBattery()
        batteryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
        refreshDeviceConnection(NixelPairingSession.shared.state)
        refreshPairingIndicator(NixelPairingSession.shared.state)
        refreshStatus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        accessTimer?.invalidate()
        batteryRefreshTimer?.invalidate()
        // No detener la sesión al cambiar de pestaña: el pairing debe seguir vivo
        // mientras el usuario cambia de pantalla para completar la operación.
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let iPadColumns else { return }
        let useTwoColumns = bounds.width >= 760
        let axis: NSLayoutConstraint.Axis = useTwoColumns ? .horizontal : .vertical
        guard iPadColumns.axis != axis else { return }
        iPadColumns.axis = axis
        iPadColumns.alignment = useTwoColumns ? .top : .fill
        iPadColumns.distribution = useTwoColumns ? .fillEqually : .fill
    }

    private func makeAccessCard() -> UIView {
        let card = DavizinCardView()
        card.contentInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let icon = UIImageView(image: UIImage(systemName: "key.horizontal.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.tintColor = AppTheme.readableAccent
        icon.backgroundColor = AppTheme.accent.withAlphaComponent(0.12)
        icon.layer.cornerRadius = 13
        icon.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42)
        ])

        let title = UILabel()
        title.text = "Acceso Nyxel"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        let heading = UIStackView(arrangedSubviews: [icon, title])
        heading.axis = .horizontal
        heading.alignment = .center
        heading.spacing = 12

        accessStatusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        accessStatusLabel.numberOfLines = 0
        keyValueLabel.font = AppTheme.monoFont(13)
        keyValueLabel.textColor = AppTheme.primaryText
        keyValueLabel.textAlignment = .right
        remainingValueLabel.font = AppTheme.monoFont(12)
        remainingValueLabel.textColor = AppTheme.readableAccent
        remainingValueLabel.textAlignment = .right

        let inner = UIStackView(arrangedSubviews: [
            heading,
            makeAccessRow(title: "Estado de acceso", value: accessStatusLabel),
            makeAccessRow(title: "Clave", value: keyValueLabel),
            makeAccessRow(title: "Vigencia", value: remainingValueLabel)
        ])
        inner.axis = .vertical
        inner.spacing = 10
        card.addContent(inner)
        updateAccessSummary()
        return card
    }

    private func makeAccessRow(title: String, value: UILabel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = AppTheme.bodyFont()
        titleLabel.textColor = AppTheme.secondaryText
        titleLabel.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [titleLabel, value])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        row.backgroundColor = AppTheme.accent.withAlphaComponent(0.055)
        row.layer.cornerRadius = 13
        row.layer.cornerCurve = .continuous
        row.layer.borderWidth = 1
        row.layer.borderColor = AppTheme.hairline.cgColor
        return row
    }

    private func updateAccessSummary() {
        let remaining = accessExpiresAt.map { max(0, Int($0.timeIntervalSinceNow)) } ?? 0
        let active = activeKey != nil && remaining > 0
        accessStatusLabel.text = activeKey == nil ? "Sin validar" : (active ? "Activa" : "Expirada")
        accessStatusLabel.textColor = active ? AppTheme.readableSuccess : AppTheme.readableWarm
        keyValueLabel.text = maskedKey(activeKey)

        if active {
            let days = remaining / 86_400
            let hours = (remaining % 86_400) / 3_600
            let minutes = (remaining % 3_600) / 60
            remainingValueLabel.text = "\(days)d · \(hours)h · \(minutes)m"
            remainingValueLabel.textColor = AppTheme.readableAccent
        } else {
            remainingValueLabel.text = activeKey == nil ? "—" : "Vencida"
            remainingValueLabel.textColor = AppTheme.readableFailure
            accessTimer?.invalidate()
            accessTimer = nil
        }
    }

    private func maskedKey(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "No disponible" }
        return key.count > 4 ? "••••-\(key.suffix(4))" : "••••"
    }

    private func refreshSystemStatus() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let label = NyxelSupportPolicy.currentSystemDescription
        let isSupported = NyxelSupportPolicy.isCurrentSystemSupported
        if version.majorVersion >= 27 {
            systemLabel.text = isSupported ? "\(label) · pairing + túnel" : "\(label) · build no verificado"
            systemLabel.textColor = isSupported ? AppTheme.readableSuccess : AppTheme.readableFailure
        } else {
            systemLabel.text = "\(label) · requiere VPN de apoyo"
            systemLabel.textColor = isSupported ? AppTheme.readableAccent : AppTheme.readableFailure
        }
        supportStatusLabel.text = isSupported ? "Compatible con Nyxel" : "Versión no verificada"
        supportStatusLabel.textColor = isSupported ? AppTheme.readableSuccess : AppTheme.readableFailure
        supportedVersionsLabel.text = NyxelSupportPolicy.supportedRangesDescription
        supportNoteLabel.text = "Este panel aplica a las versiones compatibles indicadas. En iOS 27 se requiere un build verificado y completar el flujo de emparejamiento con túnel."
    }

    @objc private func refreshStatus() {
        DispatchQueue.main.async {
            let manager = NixelVPNManager.shared
            self.statusLabel.text = NixelVPNManager.statusText(manager.status)
            self.toggleButton.setTitle(manager.isActive ? "Desconectar" : "Conectar", for: .normal)

            switch manager.status {
            case .connected:
                self.statusLabel.textColor = AppTheme.readableSuccess
                self.statusDot.backgroundColor = AppTheme.readableSuccess
            case .connecting, .reasserting:
                self.statusLabel.textColor = AppTheme.readableWarm
                self.statusDot.backgroundColor = AppTheme.readableWarm
            case .invalid, .disconnected, .disconnecting:
                self.statusLabel.textColor = AppTheme.secondaryText
                self.statusDot.backgroundColor = AppTheme.tertiaryText
            @unknown default:
                self.statusLabel.textColor = AppTheme.secondaryText
                self.statusDot.backgroundColor = AppTheme.tertiaryText
            }
        }
    }

    @objc private func toggleConnection() {
        let manager = NixelVPNManager.shared
        if manager.isActive {
            manager.stop()
            return
        }

        statusLabel.text = "Conectando…"
        statusLabel.textColor = AppTheme.readableWarm
        statusDot.backgroundColor = AppTheme.readableWarm
        toggleButton.setLoading(true, title: "Conectando")
        manager.start { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.toggleButton.setLoading(false)
                switch result {
                case .success:
                    self.refreshStatus()
                case .failure(let error):
                    NyxelActivityLog.record("iOS 27 connection setup failed: \(error.localizedDescription)")
                    self.statusLabel.text = "No se pudo conectar. Inténtalo de nuevo o revisa el estado del dispositivo."
                    self.statusLabel.textColor = AppTheme.readableFailure
                    self.statusDot.backgroundColor = AppTheme.readableFailure
                }
            }
        }
    }

    private func makeDeviceCard() -> UIView {
        let card = DavizinCardView()
        card.contentInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let title = UILabel()
        title.text = "Este dispositivo"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        for label in [deviceModelLabel, deviceConnectionLabel, batteryValueLabel] {
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = AppTheme.primaryText
            label.numberOfLines = 0
        }
        deviceModelLabel.text = NyxelSupportPolicy.currentDeviceModel

        batteryNoteLabel.text = "Carga local del iPhone o iPad que ejecuta Nyxel. La batería del dispositivo remoto todavía no está disponible en el estado de pairing actual."
        batteryNoteLabel.font = .systemFont(ofSize: 12, weight: .regular)
        batteryNoteLabel.textColor = AppTheme.secondaryText
        batteryNoteLabel.numberOfLines = 0
        batteryProgressView.translatesAutoresizingMaskIntoConstraints = false
        batteryProgressView.progress = 0
        batteryProgressView.progressTintColor = AppTheme.readableSuccess
        batteryProgressView.trackTintColor = AppTheme.hairlineStrong
        batteryProgressView.heightAnchor.constraint(equalToConstant: 6).isActive = true
        batteryProgressView.layer.cornerRadius = 3
        batteryProgressView.clipsToBounds = true
        batteryProgressView.isHidden = true
        batteryProgressView.accessibilityLabel = "Nivel de batería de este dispositivo"

        let inner = UIStackView(arrangedSubviews: [
            title,
            makeDetailStatusRow(icon: "iphone.gen3", title: "Modelo", value: deviceModelLabel),
            makeDetailStatusRow(icon: "antenna.radiowaves.left.and.right", title: "Enlace remoto", value: deviceConnectionLabel),
            makeDetailStatusRow(icon: "battery.100", title: "Batería de este dispositivo", value: batteryValueLabel),
            batteryProgressView,
            batteryNoteLabel
        ])
        inner.axis = .vertical
        inner.spacing = 10
        card.addContent(inner)
        return card
    }

    private func makeSupportCard() -> UIView {
        let card = DavizinCardView()
        card.contentInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let title = UILabel()
        title.text = "Compatibilidad y soporte"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        supportStatusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        supportStatusLabel.numberOfLines = 0
        supportedVersionsLabel.font = .systemFont(ofSize: 13, weight: .medium)
        supportedVersionsLabel.textColor = AppTheme.primaryText
        supportedVersionsLabel.numberOfLines = 0
        supportNoteLabel.font = .systemFont(ofSize: 12, weight: .regular)
        supportNoteLabel.textColor = AppTheme.secondaryText
        supportNoteLabel.numberOfLines = 0

        let inner = UIStackView(arrangedSubviews: [
            title,
            makeDetailStatusRow(icon: "checkmark.shield", title: "Sistema actual", value: supportStatusLabel),
            makeDetailStatusRow(icon: "iphone.gen3", title: "Versiones declaradas", value: supportedVersionsLabel),
            supportNoteLabel
        ])
        inner.axis = .vertical
        inner.spacing = 10
        card.addContent(inner)
        return card
    }

    @objc private func refreshBattery() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshBattery() }
            return
        }
        let device = UIDevice.current
        let level = device.batteryLevel
        guard level >= 0 else {
            batteryValueLabel.text = "Sin lectura de iOS"
            batteryValueLabel.textColor = AppTheme.secondaryText
            batteryProgressView.isHidden = true
            batteryNoteLabel.text = "iOS no está entregando el nivel de batería local; comprueba en un iPhone o iPad físico. La carga del dispositivo remoto aún no llega a esta sesión."
            return
        }

        let percent = Int((level * 100).rounded())
        let chargeState: String
        switch device.batteryState {
        case .charging: chargeState = "cargando"
        case .full: chargeState = "carga completa"
        case .unplugged: chargeState = "en batería"
        case .unknown: chargeState = "estado desconocido"
        @unknown default: chargeState = "estado desconocido"
        }
        batteryValueLabel.text = "\(percent)% · \(chargeState)"
        let levelColor = percent <= 20 ? AppTheme.readableFailure : (percent <= 50 ? AppTheme.readableWarm : AppTheme.readableSuccess)
        batteryValueLabel.textColor = levelColor
        batteryProgressView.progressTintColor = levelColor
        batteryProgressView.setProgress(Float(percent) / 100, animated: true)
        batteryProgressView.isHidden = false
        batteryProgressView.accessibilityValue = "\(percent) por ciento, \(chargeState)"
        batteryNoteLabel.text = "Carga local del iPhone o iPad que ejecuta Nyxel. La batería del dispositivo remoto todavía no está disponible en el estado de pairing actual."
    }

    private func refreshDeviceConnection(_ state: NixelPairingSessionState) {
        switch state {
        case .idle:
            deviceConnectionLabel.text = "Sin conexión"
            deviceConnectionLabel.textColor = AppTheme.secondaryText
        case .searching:
            deviceConnectionLabel.text = "Buscando dispositivo…"
            deviceConnectionLabel.textColor = AppTheme.readableWarm
        case .serviceDetected:
            deviceConnectionLabel.text = "Dispositivo detectado"
            deviceConnectionLabel.textColor = AppTheme.readableWarm
        case .transportReachable:
            deviceConnectionLabel.text = "Enlace disponible"
            deviceConnectionLabel.textColor = AppTheme.readableWarm
        case .pairingRecordFound:
            deviceConnectionLabel.text = "Registro encontrado"
            deviceConnectionLabel.textColor = AppTheme.readableWarm
        case .pairingRequired:
            deviceConnectionLabel.text = "Confirma el código"
            deviceConnectionLabel.textColor = AppTheme.readableAccent
        case .paired, .ready:
            deviceConnectionLabel.text = "Conectado"
            deviceConnectionLabel.textColor = AppTheme.readableSuccess
        case .developerModeRequired:
            deviceConnectionLabel.text = "Confirma en Ajustes"
            deviceConnectionLabel.textColor = AppTheme.readableWarm
        case .failed:
            deviceConnectionLabel.text = "Sin conexión"
            deviceConnectionLabel.textColor = AppTheme.readableFailure
        }
    }

    private func makeConnectionCard() -> UIView {
        let card = DavizinCardView()
        card.contentInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let icon = UIImageView(image: UIImage(systemName: "network"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.tintColor = AppTheme.readableAccent
        icon.backgroundColor = AppTheme.accent.withAlphaComponent(0.12)
        icon.layer.cornerRadius = 13
        icon.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42)
        ])

        let title = UILabel()
        title.text = "VPN y túnel"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        let subtitle = UILabel()
        subtitle.text = "El túnel está limitado a las rutas RSD; Internet debe seguir por la red activa (Wi‑Fi o datos). Pairing y VPN son acciones separadas."
        subtitle.font = AppTheme.bodyFont()
        subtitle.textColor = AppTheme.secondaryText
        subtitle.numberOfLines = 0

        let heading = UIStackView(arrangedSubviews: [icon, title])
        heading.axis = .horizontal
        heading.alignment = .center
        heading.spacing = 12

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.layer.cornerRadius = 4
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8)
        ])
        statusLabel.text = "No configurado"
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = AppTheme.secondaryText
        statusLabel.numberOfLines = 2
        let statusRow = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 9
        statusRow.isLayoutMarginsRelativeArrangement = true
        statusRow.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        statusRow.backgroundColor = AppTheme.accent.withAlphaComponent(0.055)
        statusRow.layer.cornerRadius = 13
        statusRow.layer.cornerCurve = .continuous
        statusRow.layer.borderWidth = 1
        statusRow.layer.borderColor = AppTheme.hairline.cgColor

        systemLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        systemLabel.numberOfLines = 0
        let systemRow = makeDetailStatusRow(icon: "iphone.gen3", title: "Sistema detectado", value: systemLabel)

        toggleButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        let inner = UIStackView(arrangedSubviews: [heading, subtitle, statusRow, systemRow, toggleButton])
        inner.axis = .vertical
        inner.spacing = 13
        card.addContent(inner)
        return card
    }

    private func makeDetailStatusRow(icon: String, title: String, value: UILabel) -> UIView {
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = AppTheme.readableAccent
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = AppTheme.bodyFont()
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [titleLabel, value])
        labels.axis = .vertical
        labels.spacing = 3
        let row = UIStackView(arrangedSubviews: [iconView, labels])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        row.backgroundColor = AppTheme.accent.withAlphaComponent(0.055)
        row.layer.cornerRadius = 13
        row.layer.cornerCurve = .continuous
        row.layer.borderWidth = 1
        row.layer.borderColor = AppTheme.hairline.cgColor
        return row
    }

    private func makePairingCard() -> UIView {
        let card = DavizinCardView()
        card.contentInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let title = UILabel()
        title.text = "Pairing"
        title.font = AppTheme.titleFont(18)
        title.textColor = AppTheme.primaryText

        pairingConnectedIcon.translatesAutoresizingMaskIntoConstraints = false
        pairingConnectedIcon.tintColor = AppTheme.readableSuccess
        NSLayoutConstraint.activate([
            pairingConnectedIcon.widthAnchor.constraint(equalToConstant: 16),
            pairingConnectedIcon.heightAnchor.constraint(equalToConstant: 16)
        ])
        pairingConnectedText.text = "Conectado"
        pairingConnectedText.font = .systemFont(ofSize: 11, weight: .bold)
        pairingConnectedText.textColor = AppTheme.readableSuccess
        pairingConnectedBadge.addArrangedSubview(pairingConnectedIcon)
        pairingConnectedBadge.addArrangedSubview(pairingConnectedText)
        pairingConnectedBadge.axis = .horizontal
        pairingConnectedBadge.alignment = .center
        pairingConnectedBadge.spacing = 5
        pairingConnectedBadge.isLayoutMarginsRelativeArrangement = true
        pairingConnectedBadge.layoutMargins = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        pairingConnectedBadge.backgroundColor = AppTheme.success.withAlphaComponent(0.12)
        pairingConnectedBadge.layer.cornerRadius = 10
        pairingConnectedBadge.layer.cornerCurve = .continuous
        pairingConnectedBadge.clipsToBounds = true
        pairingConnectedBadge.isHidden = true

        let header = UIStackView(arrangedSubviews: [title, UIView(), pairingConnectedBadge])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let subtitle = UILabel()
        subtitle.text = "Confirma la solicitud en Ajustes. El código llega en una notificación temporal."
        subtitle.font = AppTheme.bodyFont()
        subtitle.textColor = AppTheme.secondaryText
        subtitle.numberOfLines = 0

        pairingDot.translatesAutoresizingMaskIntoConstraints = false
        pairingDot.layer.cornerRadius = 4
        pairingDot.backgroundColor = AppTheme.secondaryText
        NSLayoutConstraint.activate([
            pairingDot.widthAnchor.constraint(equalToConstant: 8),
            pairingDot.heightAnchor.constraint(equalToConstant: 8)
        ])
        pairingLabel.text = "Listo para iniciar"
        pairingLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        pairingLabel.textColor = AppTheme.secondaryText
        pairingLabel.numberOfLines = 2
        let pairingStatus = UIStackView(arrangedSubviews: [pairingDot, pairingLabel])
        pairingStatus.axis = .horizontal
        pairingStatus.alignment = .center
        pairingStatus.spacing = 9
        pairingStatus.isLayoutMarginsRelativeArrangement = true
        pairingStatus.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        pairingStatus.backgroundColor = AppTheme.accent.withAlphaComponent(0.055)
        pairingStatus.layer.cornerRadius = 13
        pairingStatus.layer.cornerCurve = .continuous
        pairingStatus.layer.borderWidth = 1
        pairingStatus.layer.borderColor = AppTheme.hairline.cgColor

        pairButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let inner = UIStackView(arrangedSubviews: [header, subtitle, pairingStatus, pairButton])
        inner.axis = .vertical
        inner.spacing = 13
        card.addContent(inner)
        return card
    }

    @objc private func beginPairing() {
        pairButton.setLoading(true, title: "Preparando…")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.pairButton.setLoading(false)
                self?.startPairingSession()
            }
        }
    }

    private func startPairingSession() {
        pairingLabel.text = "Preparando vinculación…"
        pairingDot.backgroundColor = AppTheme.readableWarm
        refreshPairingIndicator(.searching)
        refreshDeviceConnection(.searching)
        NixelPairingSession.shared.begin { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pairingLabel.text = self.concisePairingMessage(for: state)
                self.refreshDeviceConnection(state)
                self.refreshPairingIndicator(state)
                switch state {
                case .failed:
                    self.pairingLabel.textColor = AppTheme.readableFailure
                    self.pairingDot.backgroundColor = AppTheme.readableFailure
                case .ready, .paired:
                    self.pairingLabel.textColor = AppTheme.readableSuccess
                    self.pairingDot.backgroundColor = AppTheme.readableSuccess
                case .pairingRequired:
                    self.pairingLabel.textColor = AppTheme.readableAccent
                    self.pairingDot.backgroundColor = AppTheme.readableAccent
                default:
                    self.pairingLabel.textColor = AppTheme.secondaryText
                    self.pairingDot.backgroundColor = AppTheme.readableWarm
                }
            }
        }
    }

    private func refreshPairingIndicator(_ state: NixelPairingSessionState) {
        switch state {
        case .ready:
            pairingConnectedText.text = "Conectado"
            pairingConnectedBadge.isHidden = false
        case .paired, .developerModeRequired:
            pairingConnectedText.text = "Vinculado"
            pairingConnectedBadge.isHidden = false
        default:
            pairingConnectedBadge.isHidden = true
        }
    }

    private func concisePairingMessage(for state: NixelPairingSessionState) -> String {
        switch state {
        case .idle:
            return "Listo para iniciar"
        case .searching:
            return "Preparando vinculación…"
        case .serviceDetected:
            return "Dispositivo detectado"
        case .transportReachable:
            return "Conexión disponible"
        case .pairingRecordFound:
            return "Registro encontrado"
        case .pairingRequired:
            return "Revisa la notificación para el código"
        case .paired:
            return "Dispositivo vinculado"
        case .developerModeRequired:
            return "Confirma la solicitud en Ajustes"
        case .ready:
            return "Vinculación lista"
        case .failed:
            return "No se completó. Vuelve a intentarlo o revisa el estado del dispositivo."
        }
    }
}
