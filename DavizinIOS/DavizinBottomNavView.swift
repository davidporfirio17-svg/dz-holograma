import UIKit

final class DavizinBottomNavView: UIView {
    var onModes: (() -> Void)?
    var onProfile: (() -> Void)?
    var onVPN: (() -> Void)?
    var onHelp: (() -> Void)?

    private let modesButton = UIButton(type: .system)
    private let profileButton = UIButton(type: .system)
    private let vpnButton = UIButton(type: .system)
    private let helpButton = UIButton(type: .system)
    private let modesLabel = UILabel()
    private let profileLabel = UILabel()
    private let vpnLabel = UILabel()
    private let helpLabel = UILabel()
    private let modesIndicator = UIView()
    private let profileIndicator = UIView()
    private let vpnIndicator = UIView()
    private let helpIndicator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setSelected(_ item: Item) {
        let selectedColor = AppTheme.readableAccent
        let normalColor = AppTheme.secondaryText
        modesButton.tintColor = item == .modes ? selectedColor : normalColor
        profileButton.tintColor = item == .profile ? selectedColor : normalColor
        vpnButton.tintColor = item == .vpn ? selectedColor : normalColor
        helpButton.tintColor = item == .help ? selectedColor : normalColor
        modesLabel.textColor = item == .modes ? selectedColor : normalColor
        profileLabel.textColor = item == .profile ? selectedColor : normalColor
        vpnLabel.textColor = item == .vpn ? selectedColor : normalColor
        helpLabel.textColor = item == .help ? selectedColor : normalColor
        UIView.animate(withDuration: AppTheme.durationPopover) {
            self.modesIndicator.alpha = item == .modes ? 1.0 : 0.0
            self.profileIndicator.alpha = item == .profile ? 1.0 : 0.0
            self.vpnIndicator.alpha = item == .vpn ? 1.0 : 0.0
            self.helpIndicator.alpha = item == .help ? 1.0 : 0.0
        }
    }

    enum Item { case modes, profile, vpn, help }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.backgroundRaise.withAlphaComponent(0.96)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = AppTheme.hairline.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.20
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        configureButton(modesButton, image: "square.grid.2x2.fill", label: modesLabel, text: "MODOS", accessibility: "Modos", action: #selector(modesTapped))
        configureButton(profileButton, image: "person.crop.circle.fill", label: profileLabel, text: "PERFIL", accessibility: "Perfil", action: #selector(profileTapped))
        configureButton(vpnButton, image: "iphone", label: vpnLabel, text: "iOS 27", accessibility: "iOS 27", action: #selector(vpnTapped))
        configureButton(helpButton, image: "questionmark.circle.fill", label: helpLabel, text: "AYUDA", accessibility: "Centro de ayuda", action: #selector(helpTapped))

        let stack = UIStackView(arrangedSubviews: [
            makeItem(button: modesButton, label: modesLabel, indicator: modesIndicator),
            makeItem(button: profileButton, label: profileLabel, indicator: profileIndicator),
            makeItem(button: vpnButton, label: vpnLabel, indicator: vpnIndicator),
            makeItem(button: helpButton, label: helpLabel, indicator: helpIndicator)
        ])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let stackTop = stack.topAnchor.constraint(equalTo: topAnchor, constant: isPad ? 8 : 6)
        let stackBottom = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: isPad ? -8 : -6)
        stackTop.priority = .defaultHigh
        stackBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isPad ? 110 : 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: isPad ? -110 : -10),
            stackTop,
            stackBottom
        ])
        setSelected(.modes)
    }

    private func configureButton(_ button: UIButton, image: String, label: UILabel, text: String, accessibility: String, action: Selector) {
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = AppTheme.secondaryText
        button.accessibilityLabel = accessibility
        button.accessibilityTraits = .button
        button.addTarget(self, action: action, for: .touchUpInside)
        label.text = text
        label.font = .systemFont(ofSize: UIDevice.current.userInterfaceIdiom == .pad ? 11 : 9, weight: .semibold)
        label.textAlignment = .center
        label.textColor = AppTheme.secondaryText
        label.isUserInteractionEnabled = false
        label.adjustsFontForContentSizeCategory = true
        label.minimumScaleFactor = 0.8
    }

    private func makeItem(button: UIButton, label: UILabel, indicator: UIView) -> UIView {
        indicator.backgroundColor = AppTheme.readableAccent
        indicator.layer.cornerRadius = 1.5
        indicator.alpha = 0.0
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.widthAnchor.constraint(equalToConstant: 26).isActive = true
        indicator.heightAnchor.constraint(equalToConstant: 2).isActive = true
        let stack = UIStackView(arrangedSubviews: [button, label, indicator])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        return stack
    }

    @objc private func modesTapped() { onModes?() }
    @objc private func profileTapped() { onProfile?() }
    @objc private func vpnTapped() { onVPN?() }
    @objc private func helpTapped() { onHelp?() }
}
