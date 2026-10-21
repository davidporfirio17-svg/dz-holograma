import UIKit

final class DavizinBottomNavView: UIView {
    var onModes: (() -> Void)?
    var onProfile: (() -> Void)?
    var onKexploit: (() -> Void)?
    var onVPN: (() -> Void)?
    var onHelp: (() -> Void)?

    enum Item { case modes, profile, kexploit, vpn, help }
    enum NavMode { case ios26, ios27 }

    private var currentMode: NavMode = .ios27
    private var currentStack: UIStackView?

    private let modesButton = UIButton(type: .system)
    private let profileButton = UIButton(type: .system)
    private let kexploitButton = UIButton(type: .system)
    private let vpnButton = UIButton(type: .system)
    private let helpButton = UIButton(type: .system)

    private let modesLabel = UILabel()
    private let profileLabel = UILabel()
    private let kexploitLabel = UILabel()
    private let vpnLabel = UILabel()
    private let helpLabel = UILabel()

    private let modesIndicator = UIView()
    private let profileIndicator = UIView()
    private let kexploitIndicator = UIView()
    private let vpnIndicator = UIView()
    private let helpIndicator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureBase()
        buildStack(for: .ios27)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBase()
        buildStack(for: .ios27)
    }

    func setMode(_ mode: NavMode) {
        guard mode != currentMode || currentStack == nil else { return }
        currentMode = mode
        buildStack(for: mode)
    }

    func setSelected(_ item: Item) {
        let selectedColor = AppTheme.readableAccent
        let normalColor = AppTheme.secondaryText

        let allButtons: [(UIButton, UILabel, UIView, Item)] = [
            (modesButton, modesLabel, modesIndicator, .modes),
            (profileButton, profileLabel, profileIndicator, .profile),
            (kexploitButton, kexploitLabel, kexploitIndicator, .kexploit),
            (vpnButton, vpnLabel, vpnIndicator, .vpn),
            (helpButton, helpLabel, helpIndicator, .help)
        ]

        for (button, label, indicator, thisItem) in allButtons {
            let isSelected = thisItem == item
            button.tintColor = isSelected ? selectedColor : normalColor
            label.textColor = isSelected ? selectedColor : normalColor
            UIView.animate(withDuration: AppTheme.durationPopover) {
                indicator.alpha = isSelected ? 1.0 : 0.0
            }
        }
    }

    private func configureBase() {
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
        configureButton(kexploitButton, image: "cpu.fill", label: kexploitLabel, text: "INICIO", accessibility: "Kexploit", action: #selector(kexploitTapped))
        configureButton(vpnButton, image: "network", label: vpnLabel, text: "CONEXIÓN", accessibility: "Conexión VPN", action: #selector(vpnTapped))
        configureButton(helpButton, image: "questionmark.circle.fill", label: helpLabel, text: "AYUDA", accessibility: "Centro de ayuda", action: #selector(helpTapped))
    }

    private func buildStack(for mode: NavMode) {
        currentStack?.removeFromSuperview()

        let items: [UIView]
        switch mode {
        case .ios27:
            modesLabel.text = "MODOS"
            items = [
                makeItem(button: modesButton, label: modesLabel, indicator: modesIndicator),
                makeItem(button: profileButton, label: profileLabel, indicator: profileIndicator),
                makeItem(button: vpnButton, label: vpnLabel, indicator: vpnIndicator),
                makeItem(button: helpButton, label: helpLabel, indicator: helpIndicator)
            ]
        case .ios26:
            kexploitLabel.text = "INICIO"
            items = [
                makeItem(button: kexploitButton, label: kexploitLabel, indicator: kexploitIndicator),
                makeItem(button: profileButton, label: profileLabel, indicator: profileIndicator),
                makeItem(button: helpButton, label: helpLabel, indicator: helpIndicator)
            ]
        }

        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        currentStack = stack

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
    @objc private func kexploitTapped() { onKexploit?() }
    @objc private func vpnTapped() { onVPN?() }
    @objc private func helpTapped() { onHelp?() }
}
