import UIKit

protocol VersionSelectorDelegate: AnyObject {
    func versionSelector(_ view: VersionSelectorView, didSelect version: VersionSelectorView.IOSPath)
}

final class VersionSelectorView: UIView {

    enum IOSPath: String {
        case ios26
        case ios27
    }

    weak var delegate: VersionSelectorDelegate?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let ios26Card = UIView()
    private let ios27Card = UIView()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let sidePadding: CGFloat = isPad ? 60 : 24

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: isPad ? 40 : 24),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: sidePadding),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -sidePadding),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -sidePadding * 2)
        ])

        configureTitles()
        configureCards()
        configureFooterNote()
    }

    private func configureTitles() {
        titleLabel.text = "Selecciona tu versión"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        subtitleLabel.text = "Elige según la versión de iOS de tu dispositivo"
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = AppTheme.secondaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 8
        headerStack.alignment = .center
        stackView.addArrangedSubview(headerStack)
        stackView.setCustomSpacing(32, after: headerStack)
    }

    private func configureCards() {
        let detected = detectIOSVersion()

        let card26 = makeCard(
            icon: "cpu.fill",
            title: "iOS 17 – 26",
            subtitle: "Kexploit · Kernel exploit directo",
            detail: "Acceso al sandbox mediante exploit del kernel.\nCierra la app y reintenta si falla.",
            accentColor: UIColor.systemOrange,
            isRecommended: detected == .ios26,
            action: #selector(didTapIOS26)
        )

        let card27 = makeCard(
            icon: "iphone.radiowaves.left.and.right",
            title: "iOS 27+",
            subtitle: "AirLift · Pairing + VPN",
            detail: "Conexión estable vía pairing y túnel VPN.\nRequiere configuración inicial.",
            accentColor: UIColor.systemBlue,
            isRecommended: detected == .ios27,
            action: #selector(didTapIOS27)
        )

        stackView.addArrangedSubview(card26)
        stackView.addArrangedSubview(card27)

        ios26Card.removeFromSuperview()
        ios27Card.removeFromSuperview()
    }

    private func makeCard(icon: String, title: String, subtitle: String, detail: String, accentColor: UIColor, isRecommended: Bool, action: Selector) -> UIView {
        let card = UIView()
        card.backgroundColor = AppTheme.card
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = isRecommended ? 2.0 : 1.0
        card.layer.borderColor = isRecommended ? accentColor.cgColor : AppTheme.hairline.cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.12
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 4)

        let iconBg = UIView()
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.backgroundColor = accentColor.withAlphaComponent(0.15)
        iconBg.layer.cornerRadius = 24
        card.addSubview(iconBg)

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = accentColor
        iconView.contentMode = .scaleAspectFit
        iconBg.addSubview(iconView)

        let titleLbl = UILabel()
        titleLbl.text = title
        titleLbl.font = .systemFont(ofSize: 22, weight: .bold)
        titleLbl.textColor = AppTheme.primaryText

        let subtitleLbl = UILabel()
        subtitleLbl.text = subtitle
        subtitleLbl.font = .systemFont(ofSize: 14, weight: .semibold)
        subtitleLbl.textColor = accentColor

        let detailLbl = UILabel()
        detailLbl.text = detail
        detailLbl.font = .systemFont(ofSize: 13, weight: .regular)
        detailLbl.textColor = AppTheme.secondaryText
        detailLbl.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLbl, subtitleLbl, detailLbl])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.setCustomSpacing(8, after: subtitleLbl)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textStack)

        var badgeView: UIView?
        if isRecommended {
            let badge = UILabel()
            badge.text = " DETECTADO "
            badge.font = .systemFont(ofSize: 11, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = accentColor
            badge.layer.cornerRadius = 6
            badge.layer.masksToBounds = true
            badge.textAlignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(badge)
            badgeView = badge
        }

        let selectBtn = UIButton(type: .system)
        selectBtn.translatesAutoresizingMaskIntoConstraints = false
        selectBtn.setTitle(isRecommended ? "SELECCIONAR ▸" : "SELECCIONAR", for: .normal)
        selectBtn.setTitleColor(.white, for: .normal)
        selectBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        selectBtn.backgroundColor = accentColor
        selectBtn.layer.cornerRadius = 14
        selectBtn.layer.cornerCurve = .continuous
        selectBtn.addTarget(self, action: action, for: .touchUpInside)
        card.addSubview(selectBtn)

        let tapGesture = UITapGestureRecognizer(target: self, action: action)
        card.addGestureRecognizer(tapGesture)
        card.isUserInteractionEnabled = true

        card.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            iconBg.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            iconBg.widthAnchor.constraint(equalToConstant: 48),
            iconBg.heightAnchor.constraint(equalToConstant: 48),

            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),

            selectBtn.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            selectBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            selectBtn.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 18),
            selectBtn.heightAnchor.constraint(equalToConstant: 50),
            selectBtn.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])

        if let badge = badgeView {
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
                badge.heightAnchor.constraint(equalToConstant: 22),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
            ])
        }

        return card
    }

    private func configureFooterNote() {
        let version = NyxelSupportPolicy.currentVersion
        let footerLabel = UILabel()
        footerLabel.text = "Tu dispositivo: iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        footerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        footerLabel.textColor = AppTheme.secondaryText
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 0
        stackView.addArrangedSubview(footerLabel)
    }

    private func detectIOSVersion() -> IOSPath {
        let version = NyxelSupportPolicy.currentVersion
        if version.majorVersion >= 27 {
            return .ios27
        }
        return .ios26
    }

    @objc private func didTapIOS26() {
        animateSelection { [weak self] in
            guard let self else { return }
            self.delegate?.versionSelector(self, didSelect: .ios26)
        }
    }

    @objc private func didTapIOS27() {
        animateSelection { [weak self] in
            guard let self else { return }
            self.delegate?.versionSelector(self, didSelect: .ios27)
        }
    }

    private func animateSelection(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 0.9
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.alpha = 1.0
                self.transform = .identity
            } completion: { _ in
                completion()
            }
        }
    }
}
