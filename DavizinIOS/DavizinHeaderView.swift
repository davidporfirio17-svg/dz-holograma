import UIKit

protocol DavizinHeaderViewDelegate: AnyObject {
    func headerViewDidTapBack(_ headerView: DavizinHeaderView)
    func headerViewDidTapClose(_ headerView: DavizinHeaderView)
    func headerViewDidTapAvatar(_ headerView: DavizinHeaderView)
    func headerViewDidLongPressAvatar(_ headerView: DavizinHeaderView)
}

final class DavizinHeaderView: UIView {
    weak var delegate: DavizinHeaderViewDelegate?

    var title: String = "" {
        didSet { titleLabel.text = title.uppercased() }
    }

    var countdownText: String = "" {
        didSet {
            countdownLabel.text = countdownText
            countdownLabel.isHidden = countdownText.isEmpty
        }
    }

	/// Color del contador (verde/amarillo/rojo segun tiempo restante).
	func setCountdownColor(_ color: UIColor) {
		countdownLabel.textColor = color
	}

	/// Muestra la versión/build del sistema y el estado de compatibilidad.
	func setSystemCompatibility(_ text: String, color: UIColor) {
		systemLabel.text = text
		systemLabel.textColor = color
		systemLabel.isHidden = text.isEmpty
	}

    var showsBackButton: Bool = true {
        didSet { backButton.isHidden = !showsBackButton }
    }

    private let titleLabel = UILabel()
    private let countdownLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let statusDot = UIView()
	private let avatarButton = UIButton(type: .system)
	private let avatarImageView = UIImageView()
	private let systemLabel = UILabel()

    /// Oculta el avatar en pantallas donde no aplica (ej: login, sin sesion).
    var showsAvatarButton: Bool = true {
        didSet { avatarButton.isHidden = !showsAvatarButton }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.card
        layer.cornerRadius = 18.0
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0
        layer.borderColor = AppTheme.hairlineStrong.cgColor

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.backgroundColor = AppTheme.accent
        statusDot.layer.cornerRadius = 4.0
        statusDot.layer.shadowColor = AppTheme.accent.cgColor
        statusDot.layer.shadowOpacity = 0.8
        statusDot.layer.shadowRadius = 7.0
        addSubview(statusDot)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .heavy)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        addSubview(titleLabel)

        configureIconButton(backButton, imageName: "chevron.left")
        configureIconButton(closeButton, imageName: "xmark")
        addSubview(backButton)
        addSubview(closeButton)

        avatarButton.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.backgroundColor = AppTheme.background
		avatarButton.layer.cornerRadius = 15.0
		avatarButton.clipsToBounds = true
        avatarButton.layer.borderWidth = 1.5
        avatarButton.layer.borderColor = AppTheme.hairlineStrong.cgColor
        avatarButton.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        let avatarLongPress = UILongPressGestureRecognizer(target: self, action: #selector(avatarLongPressed(_:)))
        avatarLongPress.minimumPressDuration = 0.45
        avatarButton.addGestureRecognizer(avatarLongPress)

		avatarImageView.image = UIImage(named: "NyxelAvatar")
		avatarImageView.contentMode = .scaleAspectFill
		avatarImageView.clipsToBounds = true
		avatarImageView.isUserInteractionEnabled = false
		avatarImageView.translatesAutoresizingMaskIntoConstraints = false
		avatarButton.addSubview(avatarImageView)
        addSubview(avatarButton)

		countdownLabel.translatesAutoresizingMaskIntoConstraints = false
		countdownLabel.textColor = AppTheme.accent
		countdownLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .bold)
		countdownLabel.textAlignment = .center
		countdownLabel.isHidden = true
		addSubview(countdownLabel)

		systemLabel.translatesAutoresizingMaskIntoConstraints = false
		systemLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
		systemLabel.textAlignment = .center
		systemLabel.numberOfLines = 1
		systemLabel.adjustsFontSizeToFitWidth = true
		systemLabel.minimumScaleFactor = 0.75
		let systemIsSupported = NyxelSupportPolicy.isCurrentSystemSupported
		systemLabel.text = "iOS/iPadOS \(NyxelSupportPolicy.currentSystemDescription) • \(systemIsSupported ? "Sistema admitido · acceso pendiente" : "No compatible")"
		systemLabel.textColor = systemIsSupported ? AppTheme.accentWarm : AppTheme.failure
		addSubview(systemLabel)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 72.0),
            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18.0),
            statusDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8.0),
            statusDot.heightAnchor.constraint(equalToConstant: 8.0),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8.0),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 12.0),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12.0),
            countdownLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			countdownLabel.topAnchor.constraint(equalTo: systemLabel.bottomAnchor, constant: 2.0),
			systemLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			systemLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.0),
			systemLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.leadingAnchor),
			systemLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleLabel.trailingAnchor),
            backButton.leadingAnchor.constraint(equalTo: avatarButton.trailingAnchor, constant: 6.0),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 34.0),
            backButton.heightAnchor.constraint(equalToConstant: 34.0),
            avatarButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8.0),
            avatarButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarButton.widthAnchor.constraint(equalToConstant: 30.0),
            avatarButton.heightAnchor.constraint(equalToConstant: 30.0),
			avatarImageView.leadingAnchor.constraint(equalTo: avatarButton.leadingAnchor),
			avatarImageView.trailingAnchor.constraint(equalTo: avatarButton.trailingAnchor),
			avatarImageView.topAnchor.constraint(equalTo: avatarButton.topAnchor),
			avatarImageView.bottomAnchor.constraint(equalTo: avatarButton.bottomAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8.0),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 38.0),
            closeButton.heightAnchor.constraint(equalToConstant: 38.0)
        ])

        titleLabel.text = title.uppercased()
        showsBackButton = true
    }

    private func configureIconButton(_ button: UIButton, imageName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = AppTheme.secondaryText
        button.backgroundColor = AppTheme.background
        button.layer.cornerRadius = 12.0
        button.accessibilityTraits = .button
        button.addTarget(self, action: #selector(iconButtonTapped(_:)), for: .touchUpInside)
    }

    @objc private func iconButtonTapped(_ sender: UIButton) {
        if sender === backButton {
            delegate?.headerViewDidTapBack(self)
        } else if sender === closeButton {
            delegate?.headerViewDidTapClose(self)
        }
    }

    @objc private func avatarTapped() {
        delegate?.headerViewDidTapAvatar(self)
    }

    @objc private func avatarLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        delegate?.headerViewDidLongPressAvatar(self)
    }
}
