import UIKit

final class HelpCenterView: UIView {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

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
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeBrandCard())
        contentStack.addArrangedSubview(makeSectionHeading())
        contentStack.addArrangedSubview(makeTopicCard(
            icon: "sparkles",
            title: "Primeros pasos",
            body: "Elige el juego instalado, selecciona un modo y sigue las instrucciones en pantalla. Si vuelves desde el juego para limpiar una sesión, usa el botón de limpieza antes de iniciar otra operación."
        ))
        contentStack.addArrangedSubview(makeTopicCard(
            icon: "person.crop.circle",
            title: "Cuenta y perfil",
            body: "En Perfil puedes revisar el estado y vencimiento de tu acceso. La clave aparece enmascarada; usa Actualizar perfil para volver a sincronizar los datos de la sesión."
        ))
        contentStack.addArrangedSubview(makeTopicCard(
            icon: "bell.badge",
            title: "Permisos y notificaciones",
            body: "Permite las notificaciones si quieres recibir el recordatorio de limpieza. Red local solo se necesita al usar el emparejamiento cercano. Puedes revisar los permisos desde Ajustes de Nyxel."
        ))
        contentStack.addArrangedSubview(makeTopicCard(
            icon: "iphone.gen3",
            title: "Compatibilidad",
            body: "La disponibilidad depende del modelo y de la versión/build de iOS o iPadOS. Nyxel muestra el dispositivo y sistema detectados en Perfil y en la pantalla iOS 27."
        ))
        contentStack.addArrangedSubview(makeSettingsButton())

        let footer = UILabel()
        footer.text = "NYXEL EXTERNAL  ·  Guía rápida"
        footer.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        footer.textColor = AppTheme.tertiaryText
        footer.textAlignment = .center
        footer.adjustsFontForContentSizeCategory = true
        footer.accessibilityTraits = .staticText
        contentStack.addArrangedSubview(footer)

        let preferredWidth = contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            contentStack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            preferredWidth
        ])
    }

    private func makeBrandCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = AppTheme.backgroundRaise
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = AppTheme.hairlineStrong.cgColor

        let avatar = UIImageView(image: UIImage(named: "NyxelAvatar"))
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 24
        avatar.layer.borderWidth = 1.5
        avatar.layer.borderColor = AppTheme.accent.withAlphaComponent(0.65).cgColor
        avatar.accessibilityLabel = "Marca Nyxel"

        let title = UILabel()
        title.text = "NYXEL EXTERNAL"
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = AppTheme.primaryText
        title.adjustsFontForContentSizeCategory = true

        let eyebrow = UILabel()
        eyebrow.text = "CENTRO DE AYUDA"
        eyebrow.font = .systemFont(ofSize: 10, weight: .bold)
        eyebrow.textColor = AppTheme.readableAccent
        eyebrow.adjustsFontForContentSizeCategory = true

        let subtitle = UILabel()
        subtitle.text = "Guías rápidas para usar la app."
        subtitle.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = AppTheme.secondaryText
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.numberOfLines = 0

        let copy = UIStackView(arrangedSubviews: [eyebrow, title, subtitle])
        copy.axis = .vertical
        copy.alignment = .leading
        copy.spacing = 4
        copy.translatesAutoresizingMaskIntoConstraints = false

        let brandRow = UIStackView(arrangedSubviews: [avatar, copy])
        brandRow.axis = .horizontal
        brandRow.alignment = .center
        brandRow.spacing = 13
        brandRow.translatesAutoresizingMaskIntoConstraints = false

        let version = UILabel()
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let ipaBuild = (Bundle.main.infoDictionary?["NyxelBuildNumber"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "local"
        version.text = "\(NyxelSupportPolicy.currentDeviceModel)  ·  \(NyxelSupportPolicy.currentSystemDescription)  ·  v\(shortVersion) (\(build))  ·  IPA #\(ipaBuild)"
        version.font = AppTheme.monoFont(10)
        version.textColor = AppTheme.tertiaryText
        version.numberOfLines = 0
        version.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [brandRow, version])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeSectionHeading() -> UIView {
        let container = UIView()
        let title = UILabel()
        title.text = "¿En qué necesitas ayuda?"
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.textColor = AppTheme.primaryText
        title.adjustsFontForContentSizeCategory = true

        let subtitle = UILabel()
        subtitle.text = "Respuestas breves a las dudas más comunes."
        subtitle.font = UIFont.preferredFont(forTextStyle: .footnote)
        subtitle.textColor = AppTheme.secondaryText
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }

    private func makeTopicCard(icon: String, title: String, body: String) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = AppTheme.backgroundRaise
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = AppTheme.hairline.cgColor

        let iconBackground = UIView()
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = AppTheme.accentDim.withAlphaComponent(0.18)
        iconBackground.layer.cornerRadius = 12

        let symbol = UIImageView(image: UIImage(systemName: icon))
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.tintColor = AppTheme.readableAccent
        symbol.contentMode = .scaleAspectFit
        iconBackground.addSubview(symbol)

        let heading = UILabel()
        heading.text = title
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.textColor = AppTheme.primaryText
        heading.adjustsFontForContentSizeCategory = true
        heading.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        bodyLabel.textColor = AppTheme.secondaryText
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true

        let header = UIStackView(arrangedSubviews: [iconBackground, heading])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [header, bodyLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            iconBackground.widthAnchor.constraint(equalToConstant: 40),
            iconBackground.heightAnchor.constraint(equalToConstant: 40),
            symbol.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            symbol.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func makeSettingsButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        button.setTitle("  ABRIR AJUSTES DE NYXEL", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        button.setTitleColor(AppTheme.accentForeground, for: .normal)
        button.tintColor = AppTheme.accentForeground
        button.backgroundColor = AppTheme.readableAccent
        button.layer.cornerRadius = 15
        button.layer.cornerCurve = .continuous
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.accessibilityIdentifier = "help.openAppSettings"
        button.accessibilityHint = "Abre los ajustes de Nyxel para revisar sus permisos."
        button.addTarget(self, action: #selector(openAppSettings), for: .touchUpInside)
        return button
    }

    @objc private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
    }
}
