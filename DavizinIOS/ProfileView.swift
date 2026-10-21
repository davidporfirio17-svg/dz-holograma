import UIKit

protocol ProfileViewDelegate: AnyObject {
    func profileViewDidTapLogout(_ view: ProfileView)
}

enum SessionStats {
    private static let key = "dz_injection_count"
    static var injectionCount: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func recordInjection() { injectionCount += 1 }
}

private struct RankTier {
    let minCount: Int
    let name: String
    let color: UIColor
}

private let rankTiers = [
    RankTier(minCount: 0, name: "BRONCE", color: UIColor(red: 0.54, green: 0.43, blue: 0.29, alpha: 1)),
    RankTier(minCount: 50, name: "PLATA", color: UIColor(red: 0.72, green: 0.77, blue: 0.80, alpha: 1)),
    RankTier(minCount: 150, name: "ORO", color: UIColor(red: 0.88, green: 0.72, blue: 0.29, alpha: 1)),
    RankTier(minCount: 300, name: "DIAMANTE", color: AppTheme.accentHot)
]

private func currentRankTier(for count: Int) -> RankTier { rankTiers.last { count >= $0.minCount } ?? rankTiers[0] }

private final class ProfileDisclosureSection: UIView {
    private let titleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
    private let bodyStack = UIStackView()
    private var collapsedHeightConstraint: NSLayoutConstraint?
    private var expanded = true

    init(title: String, views: [UIView], expanded: Bool = true) {
        self.expanded = expanded
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = AppTheme.hairline.cgColor
        backgroundColor = UIColor.white.withAlphaComponent(0.035)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = AppTheme.accent
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = AppTheme.tertiaryText
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let header = UIButton(type: .system)
        header.accessibilityLabel = "Sección \(title.lowercased())"
        header.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(titleLabel)
        addSubview(chevron)

        bodyStack.axis = .vertical
        bodyStack.spacing = 11
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        views.forEach { bodyStack.addArrangedSubview($0) }
        addSubview(bodyStack)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor), header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor), header.heightAnchor.constraint(equalToConstant: 38),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14), chevron.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bodyStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2), bodyStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
        collapsedHeightConstraint = bodyStack.heightAnchor.constraint(equalToConstant: 0)
        applyExpandedState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggle() {
        expanded.toggle()
        applyExpandedState(animated: true)
    }

    private func applyExpandedState(animated: Bool) {
        let updates = {
            self.bodyStack.isHidden = !self.expanded
            self.collapsedHeightConstraint?.isActive = !self.expanded
            self.chevron.transform = self.expanded ? .identity : CGAffineTransform(rotationAngle: -.pi / 2)
        }
        if animated { UIView.animate(withDuration: 0.2, animations: updates) } else { updates() }
    }
}

final class ProfileView: UIView {
    weak var delegate: ProfileViewDelegate?
    var onRefreshRequested: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?

    private let avatarCircle = UIView()
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let rankBadge = UIView()
    private let rankLabel = UILabel()
    private let keyValueLabel = UILabel()
    private let countryValueLabel = UILabel()
    private let expirationValueLabel = UILabel()
    private let accountStatusLabel = UILabel()
    private let countValueLabel = UILabel()
    private let serviceStatusLabel = UILabel()
    private let diagnosticsLabel = UILabel()
    private let activityLabel = UILabel()
    private let gamesLabel = UILabel()
    private let historyLabel = UILabel()
    private let deviceLabel = UILabel()
    private let rankProgressLabel = UILabel()
    private let themeControl = UISegmentedControl(items: ["Auto", "Claro", "Oscuro"])
    private let appearanceControl = UISegmentedControl(items: ["Cian", "Fuego", "Violeta"])
    private let biometricSwitch = UISwitch()
    private let activationVoiceSwitch = UISwitch()
    private let refreshButton = UIButton(type: .system)
    private let logoutButton = DavizinButton(title: "CERRAR SESIÓN", style: .destructive)
    private let scrollView = UIScrollView()
    private let progressTrack = CAShapeLayer()
    private let progressRing = CAShapeLayer()
    private var activeKey: String?
    private var activeCountryCode: String?
    private var activeRemainingSeconds = 0
    private var initialRemainingSeconds = 0

    override init(frame: CGRect) { super.init(frame: frame); configure() }
    required init?(coder: NSCoder) { super.init(coder: coder); configure() }

    func setAccount(key: String?, remainingSeconds: Int, countryCode: String? = nil) {
        let previousKey = activeKey
        activeKey = key
        if countryCode != nil { activeCountryCode = countryCode }
        if key == nil { activeCountryCode = nil }
        activeRemainingSeconds = max(0, remainingSeconds)
        if key != previousKey { initialRemainingSeconds = max(remainingSeconds, 1) }
        if initialRemainingSeconds == 0 { initialRemainingSeconds = max(remainingSeconds, 1) }
        refresh()
    }

    func refresh() {
        let count = SessionStats.injectionCount
        let tier = currentRankTier(for: count)
        rankLabel.text = "◆ \(tier.name)"
        rankLabel.textColor = tier.color
        rankBadge.layer.borderColor = tier.color.withAlphaComponent(0.5).cgColor
        rankBadge.backgroundColor = tier.color.withAlphaComponent(0.12)
        keyValueLabel.text = maskedKey(activeKey)
        countryValueLabel.text = countryName(for: activeCountryCode)
        accountStatusLabel.text = activeKey == nil ? "Sin validar" : (activeRemainingSeconds > 0 ? "Activa" : "Expirada")
        accountStatusLabel.textColor = activeRemainingSeconds > 0 ? AppTheme.success : AppTheme.failure
        expirationValueLabel.text = formattedRemaining(activeRemainingSeconds)
        countValueLabel.text = "\(count)"
        let next = rankTiers.first(where: { $0.minCount > count })?.minCount
        rankProgressLabel.text = next.map { "Progreso de rango: \(count)/\($0)" } ?? "Progreso de rango: máximo alcanzado"
        deviceLabel.text = "NYXEL EXTERNAL\n\(KeyValidator.getDeviceModel()) • \(NyxelSupportPolicy.currentSystemDescription)"
        themeControl.selectedSegmentIndex = NyxelAppearanceStore.colorMode.rawValue
        appearanceControl.selectedSegmentIndex = NyxelAppearanceStore.theme.rawValue
        biometricSwitch.isOn = UserDefaults.standard.bool(forKey: "nyxel.biometric.enabled")
        activationVoiceSwitch.isOn = SoundService.shared.activationVoiceEnabled
        serviceStatusLabel.text = "●  \(NyxelRemoteConfigStore.status)"
        serviceStatusLabel.textColor = NyxelRemoteConfigStore.status == "Configuración válida" ? AppTheme.success : AppTheme.warm
        diagnosticsLabel.text = diagnosticText()
        gamesLabel.text = NyxelInstalledGames.statusText()
        let history = NyxelActivityLog.entries
        historyLabel.text = history.isEmpty ? "HISTORIAL\nSin actividad registrada" : "HISTORIAL\n" + history.joined(separator: "\n")
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        activityLabel.text = "Última actividad  •  Perfil consultado a las \(formatter.string(from: Date()))"
        updateProgressRing()
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        avatarCircle.backgroundColor = AppTheme.card
        avatarCircle.layer.cornerRadius = 31
        avatarCircle.layer.borderWidth = 2
        avatarCircle.layer.borderColor = AppTheme.accent.cgColor
        avatarCircle.layer.shadowColor = AppTheme.accent.cgColor
        avatarCircle.layer.shadowOpacity = 0.16
        avatarCircle.layer.shadowRadius = 9
        avatarCircle.clipsToBounds = true
        avatarCircle.translatesAutoresizingMaskIntoConstraints = false

        avatarImageView.image = UIImage(named: "NyxelAvatar")
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarCircle.addSubview(avatarImageView)
        progressTrack.fillColor = UIColor.clear.cgColor
        progressTrack.strokeColor = AppTheme.hairlineStrong.cgColor
        progressTrack.lineWidth = 3
        progressRing.fillColor = UIColor.clear.cgColor
        progressRing.strokeColor = AppTheme.accent.cgColor
        progressRing.lineWidth = 3
        progressRing.lineCap = .round
        avatarImageView.layer.addSublayer(progressTrack)
        avatarImageView.layer.addSublayer(progressRing)

        nameLabel.text = "NYXEL EXTERNAL"
        nameLabel.font = AppTheme.titleFont(19)
        nameLabel.textColor = AppTheme.primaryText
        rankLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        rankLabel.translatesAutoresizingMaskIntoConstraints = false
        rankBadge.layer.cornerRadius = 100
        rankBadge.layer.borderWidth = 1
        rankBadge.translatesAutoresizingMaskIntoConstraints = false
        rankBadge.addSubview(rankLabel)

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, rankBadge])
        nameStack.axis = .vertical; nameStack.alignment = .leading; nameStack.spacing = 6
        let heroStack = UIStackView(arrangedSubviews: [avatarCircle, nameStack])
        heroStack.axis = .horizontal; heroStack.alignment = .center; heroStack.spacing = 16
        heroStack.translatesAutoresizingMaskIntoConstraints = false

        let keyRow = makeRow(label: "Key", valueLabel: keyValueLabel)
        let countryRow = makeRow(label: "País", valueLabel: countryValueLabel)
        let statusRow = makeRow(label: "Estado", valueLabel: accountStatusLabel)
        let expirationRow = makeRow(label: "Expira en", valueLabel: expirationValueLabel)
        let countRow = makeRow(label: "Inyecciones totales", valueLabel: countValueLabel)

        serviceStatusLabel.font = AppTheme.monoFont(11)
        diagnosticsLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        diagnosticsLabel.textColor = AppTheme.secondaryText
        diagnosticsLabel.numberOfLines = 0
        activityLabel.font = .systemFont(ofSize: 10, weight: .medium)
        activityLabel.textColor = AppTheme.tertiaryText
        activityLabel.numberOfLines = 0
        gamesLabel.font = AppTheme.monoFont(10)
        gamesLabel.textColor = AppTheme.secondaryText
        gamesLabel.numberOfLines = 0
        historyLabel.font = AppTheme.monoFont(10)
        historyLabel.textColor = AppTheme.tertiaryText
        historyLabel.numberOfLines = 0
        deviceLabel.font = AppTheme.monoFont(10)
        deviceLabel.textColor = AppTheme.secondaryText
        deviceLabel.numberOfLines = 0
        rankProgressLabel.font = AppTheme.monoFont(10)
        rankProgressLabel.textColor = AppTheme.accentHot
        configureSegmentedControl(themeControl)
        configureSegmentedControl(appearanceControl)
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)
        appearanceControl.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        biometricSwitch.onTintColor = AppTheme.accent
        biometricSwitch.addTarget(self, action: #selector(biometricChanged), for: .valueChanged)
        activationVoiceSwitch.onTintColor = AppTheme.accent
        activationVoiceSwitch.addTarget(self, action: #selector(activationVoiceChanged), for: .valueChanged)

        refreshButton.setTitle("↻  ACTUALIZAR PERFIL", for: .normal)
        refreshButton.setTitleColor(AppTheme.accent, for: .normal)
        refreshButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .heavy)
        refreshButton.backgroundColor = AppTheme.accentDim.withAlphaComponent(0.72)
        refreshButton.layer.cornerRadius = 10
        refreshButton.layer.borderWidth = 1
        refreshButton.layer.borderColor = AppTheme.accent.withAlphaComponent(0.35).cgColor
        refreshButton.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let card = DavizinCardView()
        card.useTransparentAppearance()
        let biometricRow = UIStackView(arrangedSubviews: [makeCaptionLabel("Face ID / Touch ID antes de inyectar"), biometricSwitch])
        biometricRow.axis = .horizontal
        biometricRow.alignment = .center
        biometricRow.distribution = .equalSpacing
        let activationVoiceRow = UIStackView(arrangedSubviews: [makeCaptionLabel("Audio \"Opción activada\" después de inyectar"), activationVoiceSwitch])
        activationVoiceRow.axis = .horizontal
        activationVoiceRow.alignment = .center
        activationVoiceRow.distribution = .equalSpacing
        let themeRow = UIStackView(arrangedSubviews: [makeCaptionLabel("Tema de la interfaz"), themeControl])
        themeRow.axis = .vertical
        themeRow.spacing = 8
        let accentRow = UIStackView(arrangedSubviews: [makeCaptionLabel("Color de acento"), appearanceControl])
        accentRow.axis = .vertical
        accentRow.spacing = 8

        let accountSection = ProfileDisclosureSection(title: "CUENTA", views: [keyRow, countryRow, statusRow, expirationRow, countRow, rankProgressLabel, deviceLabel])
        let appearanceSection = ProfileDisclosureSection(title: "APARIENCIA", views: [themeRow, accentRow])
        let securitySection = ProfileDisclosureSection(title: "SEGURIDAD", views: [biometricRow])
        let audioSection = ProfileDisclosureSection(title: "AUDIO", views: [activationVoiceRow])
        let diagnosticSection = ProfileDisclosureSection(title: "DIAGNÓSTICO", views: [serviceStatusLabel, diagnosticsLabel, gamesLabel], expanded: false)
        let activitySection = ProfileDisclosureSection(title: "ACTIVIDAD", views: [historyLabel, activityLabel], expanded: false)
        let stack = UIStackView(arrangedSubviews: [heroStack, accountSection, appearanceSection, securitySection, audioSection, diagnosticSection, activitySection, refreshButton, logoutButton])
        stack.axis = .vertical; stack.spacing = 15
        stack.setCustomSpacing(22, after: heroStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addContent(stack)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.indicatorStyle = .white
        addSubview(scrollView)
        scrollView.addSubview(card)

        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            avatarCircle.widthAnchor.constraint(equalToConstant: 62), avatarCircle.heightAnchor.constraint(equalToConstant: 62),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarCircle.leadingAnchor), avatarImageView.trailingAnchor.constraint(equalTo: avatarCircle.trailingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: avatarCircle.topAnchor), avatarImageView.bottomAnchor.constraint(equalTo: avatarCircle.bottomAnchor),
            rankBadge.heightAnchor.constraint(equalToConstant: 22), rankLabel.leadingAnchor.constraint(equalTo: rankBadge.leadingAnchor, constant: 10),
            rankLabel.trailingAnchor.constraint(equalTo: rankBadge.trailingAnchor, constant: -10), rankLabel.centerYAnchor.constraint(equalTo: rankBadge.centerYAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor), scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor), card.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 22),
            card.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -22),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 22), card.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -22),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 680 : AppTheme.contentMaximumWidth), stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            logoutButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight)
        ])
        refresh()
    }

    private func makeRow(label: String, valueLabel: UILabel) -> UIView {
        let left = UILabel(); left.text = label; left.font = .systemFont(ofSize: 13, weight: .medium); left.textColor = AppTheme.secondaryText
        valueLabel.font = AppTheme.monoFont(13); valueLabel.textColor = AppTheme.accentHot; valueLabel.textAlignment = .right
        let row = UIStackView(arrangedSubviews: [left, valueLabel]); row.axis = .horizontal; row.distribution = .equalSpacing
        return row
    }

    @objc private func refreshTapped() {
        refreshButton.isEnabled = false
        refreshButton.setTitle("↻  ACTUALIZANDO...", for: .normal)
        onRefreshRequested?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshButton.isEnabled = true
            self?.refreshButton.setTitle("↻  ACTUALIZAR PERFIL", for: .normal)
            self?.refresh()
        }
    }

    @objc private func logoutTapped() { SoundService.shared.playClick(); delegate?.profileViewDidTapLogout(self) }

    @objc private func appearanceChanged() {
        let theme = NyxelAppearanceStore.Theme(rawValue: appearanceControl.selectedSegmentIndex) ?? .cyan
        NyxelAppearanceStore.setTheme(theme)
        onAppearanceChanged?()
    }

    @objc private func themeChanged() {
        let mode = NyxelAppearanceStore.ColorMode(rawValue: themeControl.selectedSegmentIndex) ?? .automatic
        NyxelAppearanceStore.setColorMode(mode)
        onAppearanceChanged?()
    }

    private func configureSegmentedControl(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = AppTheme.accent
        control.setTitleTextAttributes([.foregroundColor: AppTheme.background], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: AppTheme.secondaryText], for: .normal)
    }

    @objc private func biometricChanged() {
        UserDefaults.standard.set(biometricSwitch.isOn, forKey: "nyxel.biometric.enabled")
        NyxelActivityLog.record(biometricSwitch.isOn ? "Biometría activada" : "Biometría desactivada")
    }

    @objc private func activationVoiceChanged() {
        SoundService.shared.activationVoiceEnabled = activationVoiceSwitch.isOn
        NyxelActivityLog.record(activationVoiceSwitch.isOn ? "Audio de confirmación activado" : "Audio de confirmación desactivado")
    }

    private func makeCaptionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = AppTheme.secondaryText
        return label
    }

    private func maskedKey(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "—" }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 8 else { return String(repeating: "•", count: value.count) }
        return "\(value.prefix(4))••••\(value.suffix(4))"
    }

    private func formattedRemaining(_ seconds: Int) -> String {
        guard seconds > 0 else { return activeKey == nil ? "—" : "Expirada" }
        let d = seconds / 86400; let h = (seconds % 86400) / 3600; let m = (seconds % 3600) / 60; let s = seconds % 60
        if d > 0 { return String(format: "%dd %02dh %02dm", d, h, m) }
        return String(format: "%02dh %02dm %02ds", h, m, s)
    }

    private func countryName(for code: String?) -> String {
        guard let code, !code.isEmpty else { return "País no disponible" }
        let names = ["MX": "México", "GT": "Guatemala", "US": "Estados Unidos", "CA": "Canadá", "ES": "España", "CO": "Colombia", "AR": "Argentina", "CL": "Chile", "PE": "Perú", "BR": "Brasil", "DO": "República Dominicana", "HN": "Honduras", "SV": "El Salvador", "CR": "Costa Rica", "PA": "Panamá", "NI": "Nicaragua", "VE": "Venezuela", "EC": "Ecuador", "BO": "Bolivia", "UY": "Uruguay", "PY": "Paraguay", "PR": "Puerto Rico", "EU": "Europa"]
        let normalized = code.uppercased()
        return names[normalized].map { "\(normalized) · \($0)" } ?? normalized
    }

    private func diagnosticText() -> String {
        let system = NyxelSupportPolicy.currentSystemDescription
        let compatibility = NyxelSupportPolicy.isCurrentSystemSupported ? "Compatible" : "No compatible"
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return "Sistema: \(system)\nCompatibilidad: \(compatibility)\nHora local: \(formatter.string(from: Date()))\nNyxel: v\(version)\nConfiguración: \(NyxelRemoteConfigStore.status) (\(NyxelRemoteConfigStore.ageDescription))"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = avatarImageView.bounds.insetBy(dx: 5, dy: 5)
        let path = UIBezierPath(ovalIn: rect).cgPath
        progressTrack.frame = avatarImageView.bounds; progressRing.frame = avatarImageView.bounds
        progressTrack.path = path; progressRing.path = path
        updateProgressRing()
    }

    private func updateProgressRing() {
        let progress = initialRemainingSeconds > 0 ? max(0, min(1, CGFloat(activeRemainingSeconds) / CGFloat(initialRemainingSeconds))) : 0
        progressRing.strokeEnd = progress
        progressRing.strokeColor = activeRemainingSeconds <= 3600 ? AppTheme.failure.cgColor : AppTheme.accent.cgColor
    }
}
