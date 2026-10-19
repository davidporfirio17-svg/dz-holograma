import UIKit

// MARK: - DavizinModeSheet — equivalente nativo de Vaul (vaul-main/src/index.tsx + constants.ts)
// UISheetPresentationController ya implementa nativamente lo que Vaul hace a mano en web:
// drag con damping, snap points, velocity threshold para cerrar. Se configuran los mismos
// parámetros de vaul/constants.ts donde el sistema nativo lo permite:
//   BORDER_RADIUS = 8 -> preferredCornerRadius
//   detents (Vaul snapPoints) -> [.medium(), .large()]
//
// Usa el DavizinMode real de UIState.swift (id, label, oneTime, consumed, etc.)
// — no redefine el modelo.

protocol DavizinModeSheetDelegate: AnyObject {
    func modeSheet(_ sheet: DavizinModeSheetViewController, didSelect mode: DavizinMode)
}

/// Icono y descripción visual por id de modo. Si llega un modo nuevo desde el
/// Worker que no está en esta tabla, cae a un ícono/descr. genéricos.
private extension DavizinMode {
    var symbol: String {
        return "▸"
    }

    var sheetDescription: String {
        if !noticeBody.isEmpty { return noticeBody }
        return "Modo de inyección"
    }
}

final class DavizinModeSheetViewController: UIViewController {
    weak var delegate: DavizinModeSheetDelegate?

    private let modes: [DavizinMode]
    private var selectedIndex: Int?
    private let stack = UIStackView()

    init(modes: [DavizinMode]) {
        self.modes = modes
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20   // Vaul BORDER_RADIUS visualmente escalado a iOS
            sheet.largestUndimmedDetentIdentifier = nil
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppTheme.background

        let title = UILabel()
        title.text = "Seleccionar modo"
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textColor = AppTheme.primaryText

        let desc = UILabel()
        desc.text = "Arrastra hacia abajo para cerrar."
        desc.font = .systemFont(ofSize: 13, weight: .regular)
        desc.textColor = AppTheme.secondaryText

        let header = UIStackView(arrangedSubviews: [title, desc])
        header.axis = .vertical
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        if modes.isEmpty {
            let empty = UILabel()
            empty.text = "No hay modos activos. Activa al menos uno desde el panel."
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = AppTheme.tertiaryText
            empty.numberOfLines = 0
            stack.addArrangedSubview(empty)
        }

        for (index, mode) in modes.enumerated() {
            let row = DavizinModeRow(mode: mode)
            row.tag = index
            row.onTap = { [weak self] in self?.select(index) }
            stack.addArrangedSubview(row)
        }

        view.addSubview(header)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),

            stack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14)
        ])

        animateItemsIn()
    }

    /// Cascada de entrada, igual patrón que las cards de Vaul/Sonner: stagger 40-60ms,
    /// translateY(16) + opacity, ease-out — valores de animate/SKILL.md tabla Duration.
    private func animateItemsIn() {
        for (i, row) in stack.arrangedSubviews.enumerated() {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: 0, y: 16)
            UIView.animate(
                withDuration: 0.25,
                delay: Double(i) * 0.05,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.3,
                options: [.curveEaseOut]
            ) {
                row.alpha = 1
                row.transform = .identity
            }
        }
    }

    private func select(_ index: Int) {
        guard index >= 0, index < modes.count else { return }
        selectedIndex = index
        for case let row as DavizinModeRow in stack.arrangedSubviews {
            row.setSelected(row.tag == index, animated: true)
        }
        // Delay corto para que se vea el check antes de cerrar — mismo patrón que
        // el drawer de Vaul que cierra tras onDragSnapPoints resolver.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self = self else { return }
            let mode = self.modes[index]
            self.dismiss(animated: true) {
                self.delegate?.modeSheet(self, didSelect: mode)
            }
        }
    }
}

// MARK: - Fila de modo individual

final class DavizinModeRow: UIView {
    var onTap: (() -> Void)?
    private let iconContainer = UIView()
    private let iconLabel = UILabel()
    private let nameLabel = UILabel()
    private let descLabel = UILabel()
    private let checkView = UIView()
    private let checkmark = UIImageView()

    init(mode: DavizinMode) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = true

        iconContainer.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        iconContainer.layer.cornerRadius = 10
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        iconLabel.text = mode.symbol
        iconLabel.font = .systemFont(ofSize: 16)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.text = mode.displayName
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.textColor = AppTheme.primaryText

        descLabel.text = mode.sheetDescription
        descLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = AppTheme.tertiaryText
        descLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [nameLabel, descLabel])
        textStack.axis = .vertical
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        checkView.layer.cornerRadius = 9
        checkView.layer.borderWidth = 1.5
        checkView.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        checkView.translatesAutoresizingMaskIntoConstraints = false

        checkmark.image = UIImage(systemName: "checkmark")
        checkmark.tintColor = .white
        checkmark.contentMode = .scaleAspectFit
        checkmark.alpha = 0
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.addSubview(iconLabel)
        checkView.addSubview(checkmark)
        addSubview(iconContainer)
        addSubview(textStack)
        addSubview(checkView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64),

            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36),
            iconLabel.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -12),

            checkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 18),
            checkView.heightAnchor.constraint(equalToConstant: 18),
            checkmark.widthAnchor.constraint(equalToConstant: 10),
            checkmark.heightAnchor.constraint(equalToConstant: 10),
            checkmark.centerXAnchor.constraint(equalTo: checkView.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: checkView.centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() {
        UIView.animate(withDuration: AppTheme.durationButtonPress, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.backgroundColor = AppTheme.accentDim
        } completion: { _ in
            self.onTap?()
        }
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        let apply = {
            self.iconContainer.backgroundColor = selected ? AppTheme.accent : UIColor.white.withAlphaComponent(0.06)
            self.checkView.backgroundColor = selected ? AppTheme.accent : .clear
            self.checkView.layer.borderColor = (selected ? AppTheme.accent : UIColor.white.withAlphaComponent(0.16)).cgColor
            self.checkmark.alpha = selected ? 1 : 0
            self.backgroundColor = selected ? AppTheme.accentDim : .clear
        }
        if animated {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut], animations: apply)
        } else {
            apply()
        }
    }
}
