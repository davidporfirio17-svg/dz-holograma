import UIKit

protocol ModeSelectionViewDelegate: AnyObject {
    func modeSelectionView(_ view: ModeSelectionView, didSelect mode: DavizinMode)
    /// El VC decide cómo presentar el sheet nativo (necesita un UIViewController real).
    func modeSelectionViewDidRequestSheet(_ view: ModeSelectionView)
}

final class ModeSelectionView: UIView {
    weak var delegate: ModeSelectionViewDelegate?

    private let cardView = DavizinCardView()
    private let categoryLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let footerLabel = UILabel()
    private let sheetTriggerButton = DavizinButton(title: "Ver todos los modos", style: .primary)
    private let stackView = UIStackView()

    /// Un botón por cada caso de DavizinMode, en el mismo orden del enum.
    private var modeButtons: [(mode: DavizinMode, button: DavizinButton)] = []

    private(set) var selectedMode: DavizinMode?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setSelectedMode(_ mode: DavizinMode?) {
        selectedMode = mode
        for entry in modeButtons {
            entry.button.selectedVisual = (entry.mode == mode)
        }
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        categoryLabel.text = "02  ·  CONFIGURACIÓN"
        categoryLabel.textColor = AppTheme.tertiaryText
        categoryLabel.font = AppTheme.captionFont()
        categoryLabel.textAlignment = .center
        categoryLabel.adjustsFontForContentSizeCategory = true
        applyTitleTracking(categoryLabel, value: 1.2)

        titleLabel.text = "Elige tu modo"
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.font = AppTheme.titleFont()
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.text = "Selecciona una configuración para esta sesión."
        subtitleLabel.textColor = AppTheme.secondaryText
        subtitleLabel.font = AppTheme.bodyFont()
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        footerLabel.text = "Puedes cambiar de modo antes de iniciar la operación."
        footerLabel.textColor = AppTheme.secondaryText
        footerLabel.font = AppTheme.captionFont()
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 0
        footerLabel.adjustsFontForContentSizeCategory = true

        sheetTriggerButton.addTarget(self, action: #selector(sheetTriggerTapped), for: .touchUpInside)
        sheetTriggerButton.accessibilityIdentifier = "mode.openSheet"

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 14.0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(categoryLabel)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(sheetTriggerButton)

        var buttonConstraints: [NSLayoutConstraint] = [
            sheetTriggerButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight)
        ]

        let activeModes = DavizinModeCatalog.enabledModes()
        if activeModes.isEmpty {
            footerLabel.text = "No hay modos activos. Activa al menos uno desde el panel."
        }
        for (index, mode) in activeModes.enumerated() {
            let button = DavizinButton(title: "  \(mode.displayName)\n  DISPONIBLE", style: .secondary)
            button.accessibilityIdentifier = accessibilityIdentifier(for: mode)
            button.accessibilityHint = mode.noticeBody.isEmpty ? "Selecciona este modo para continuar." : mode.noticeBody
            button.contentHorizontalAlignment = .left
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.titleLabel?.textAlignment = .left
            button.setImage(UIImage(systemName: iconName(for: mode)), for: .normal)
            button.tintColor = AppTheme.accent
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 12)
            button.tag = index
            button.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)

            stackView.addArrangedSubview(button)
            buttonConstraints.append(
                button.heightAnchor.constraint(equalToConstant: 64.0)
            )

            modeButtons.append((mode: mode, button: button))
        }

        stackView.addArrangedSubview(footerLabel)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.useTransparentAppearance()
        cardView.addContent(stackView)
        addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 22.0),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22.0),
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 580.0 : AppTheme.contentMaximumWidth),
            stackView.widthAnchor.constraint(greaterThanOrEqualToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 360.0 : 240.0)
        ] + buttonConstraints)
    }

    private func accessibilityIdentifier(for mode: DavizinMode) -> String {
        return "mode." + mode.id
    }

    private func iconName(for mode: DavizinMode) -> String {
        mode.accessTier == "pro" ? "lock.shield.fill" : "slider.horizontal.3"
    }

    @objc private func sheetTriggerTapped() {
        delegate?.modeSelectionViewDidRequestSheet(self)
    }

    @objc private func modeTapped(_ sender: DavizinButton) {
        let cases = DavizinModeCatalog.enabledModes()
        guard sender.tag >= 0, sender.tag < cases.count else { return }
        let mode = cases[sender.tag]
        setSelectedMode(mode)
        delegate?.modeSelectionView(self, didSelect: mode)
    }
}
