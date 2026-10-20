import UIKit

protocol GameSelectionViewDelegate: AnyObject {
    func gameSelectionView(_ view: GameSelectionView, didSelect game: DavizinGame)
}

final class GameSelectionView: UIView {
    weak var delegate: GameSelectionViewDelegate?

    private let cardView = DavizinCardView()
    private let categoryLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let freeFireButton = DavizinButton(title: "FREE FIRE", style: .secondary)
    private let freeFireMaxButton = DavizinButton(title: "FREE FIRE MAX", style: .secondary)
    private let freeFireSubtitle = UILabel()
    private let freeFireMaxSubtitle = UILabel()
    private let freeFireCompatibility = UILabel()
    private let freeFireMaxCompatibility = UILabel()
    private let stackView = UIStackView()

    private(set) var selectedGame: DavizinGame?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setSelectedGame(_ game: DavizinGame?) {
        selectedGame = game
        freeFireButton.selectedVisual = game == .freeFire
        freeFireMaxButton.selectedVisual = game == .freeFireMax
        freeFireSubtitle.text = game == .freeFire ? "✓ SELECCIONADO · ESTÁNDAR" : "Entorno estándar"
        freeFireMaxSubtitle.text = game == .freeFireMax ? "✓ SELECCIONADO · OPTIMIZADO" : "Entorno optimizado"
        freeFireSubtitle.textColor = game == .freeFire ? AppTheme.accent : AppTheme.tertiaryText
        freeFireMaxSubtitle.textColor = game == .freeFireMax ? AppTheme.accent : AppTheme.tertiaryText
        refreshCompatibilityIndicators()
    }

    private func refreshCompatibilityIndicators() {
        let systemOK = NyxelSupportPolicy.isCurrentSystemSupported
        let freeFireOK = systemOK && InjectorService.isBundleAvailable(for: .freeFire)
        let freeFireMaxOK = systemOK && InjectorService.isBundleAvailable(for: .freeFireMax)
        freeFireCompatibility.text = freeFireOK ? "● Bundle compatible" : "● Bundle no compatible"
        freeFireMaxCompatibility.text = freeFireMaxOK ? "● Bundle compatible" : "● Bundle no compatible"
        freeFireCompatibility.textColor = freeFireOK ? AppTheme.success : AppTheme.failure
        freeFireMaxCompatibility.textColor = freeFireMaxOK ? AppTheme.success : AppTheme.failure
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        categoryLabel.text = "01 / ENTORNO"
        categoryLabel.textColor = AppTheme.tertiaryText
        categoryLabel.font = AppTheme.captionFont()
        categoryLabel.textAlignment = .center
        categoryLabel.adjustsFontForContentSizeCategory = true
        applyTitleTracking(categoryLabel, value: 1.2)

        titleLabel.text = "Elige tu entorno"
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.font = AppTheme.titleFont()
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.text = "Selecciona la versión que quieres preparar."
        subtitleLabel.textColor = AppTheme.secondaryText
        subtitleLabel.font = AppTheme.bodyFont()
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = AppTheme.secondaryText.withAlphaComponent(0.78)

        freeFireButton.accessibilityIdentifier = "game.freeFire"
        freeFireMaxButton.accessibilityIdentifier = "game.freeFireMax"
        freeFireButton.accessibilityValue = "Entorno estándar"
        freeFireButton.accessibilityHint = "Selecciona Free Fire como entorno."
        freeFireMaxButton.accessibilityValue = "Entorno optimizado"
        freeFireMaxButton.accessibilityHint = "Selecciona Free Fire MAX como entorno."
        freeFireButton.setImage(UIImage(systemName: "flame.fill"), for: .normal)
        freeFireMaxButton.setImage(UIImage(systemName: "flame.circle.fill"), for: .normal)
        freeFireButton.tintColor = AppTheme.accent
        freeFireMaxButton.tintColor = AppTheme.accent
        freeFireButton.contentHorizontalAlignment = .left
        freeFireMaxButton.contentHorizontalAlignment = .left
        freeFireSubtitle.text = "Entorno estándar"
        freeFireMaxSubtitle.text = "Entorno optimizado"
        [freeFireSubtitle, freeFireMaxSubtitle].forEach {
            $0.font = AppTheme.captionFont()
            $0.textAlignment = .left
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        [freeFireCompatibility, freeFireMaxCompatibility].forEach {
            $0.font = AppTheme.captionFont()
            $0.textAlignment = .left
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        refreshCompatibilityIndicators()
        freeFireButton.addTarget(self, action: #selector(freeFireTapped), for: .touchUpInside)
        freeFireMaxButton.addTarget(self, action: #selector(freeFireMaxTapped), for: .touchUpInside)

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(categoryLabel)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        let freeFireChoice = UIStackView(arrangedSubviews: [freeFireButton, freeFireSubtitle, freeFireCompatibility])
        let freeFireMaxChoice = UIStackView(arrangedSubviews: [freeFireMaxButton, freeFireMaxSubtitle, freeFireMaxCompatibility])
        [freeFireChoice, freeFireMaxChoice].forEach {
            $0.axis = .vertical
            $0.alignment = .fill
            $0.spacing = 3.0
        }
        stackView.addArrangedSubview(freeFireChoice)
        stackView.addArrangedSubview(freeFireMaxChoice)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.useTransparentAppearance()
        cardView.addContent(stackView)
        addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 22.0),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22.0),
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 560.0 : AppTheme.contentMaximumWidth),
            stackView.widthAnchor.constraint(greaterThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 360.0 : 240.0),
            freeFireButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight),
            freeFireMaxButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight),
            freeFireSubtitle.heightAnchor.constraint(equalToConstant: 14.0),
            freeFireMaxSubtitle.heightAnchor.constraint(equalToConstant: 14.0),
            freeFireCompatibility.heightAnchor.constraint(equalToConstant: 14.0),
            freeFireMaxCompatibility.heightAnchor.constraint(equalToConstant: 14.0)
        ])
    }

    @objc private func freeFireTapped() {
        setSelectedGame(.freeFire)
        delegate?.gameSelectionView(self, didSelect: .freeFire)
    }

    @objc private func freeFireMaxTapped() {
        setSelectedGame(.freeFireMax)
        delegate?.gameSelectionView(self, didSelect: .freeFireMax)
    }
}
