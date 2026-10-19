import UIKit

// MARK: - MissionMapView — reemplaza ModeSelectionView como pantalla de "elegir modo".
// Es una UIView (no un UIViewController) para vivir dentro del mismo
// contentContainerView que Login/Entorno/Operacion, y asi heredar el
// header persistente (con back, X, y el reloj de countdown).
// Nodos conectados por curvas (CAShapeLayer), respiracion idle, y una
// particula que viaja por cada linea.

protocol MissionMapViewDelegate: AnyObject {
    func missionMapView(_ view: MissionMapView, didSelect mode: DavizinMode)
    func missionMapViewDidRequestRefresh(_ view: MissionMapView)
}

final class MissionMapView: UIView {
    weak var delegate: MissionMapViewDelegate?
    private var modes: [DavizinMode] = []
    private var nodeViews: [MissionNodeView] = []
    private let scrollView = UIScrollView()
    private let canvas = UIView()
    private var canvasHeight: CGFloat = 460
    private var connectionsDrawn = false
    private var canvasHeightConstraint: NSLayoutConstraint?
    private let scrollHint = UILabel()
    private let modeStatusLabel = UILabel()
    private let syncButton = UIButton(type: .system)

    /// Genera posiciones en zigzag para cualquier cantidad de modos (ya no
    /// esta fijo a 3 — antes, si el Worker mandaba mas modos, se dibujaban
    /// encima de los primeros y los tapaban).
    private func generatePositions(count: Int) -> [CGPoint] {
		guard count > 0 else { return [] }
		var points: [CGPoint] = []
		let topInset: CGFloat = 48
		let verticalSpacing: CGFloat = 108
		for i in 0..<count {
			let side: CGFloat = i % 2 == 0 ? 0.28 : 0.60
			let y = (topInset + CGFloat(i) * verticalSpacing) / canvasHeight
            points.append(CGPoint(x: side, y: y))
        }
        return points
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setModes(_ modes: [DavizinMode], selected: DavizinMode?) {
        self.modes = modes
        nodeViews.forEach { $0.removeFromSuperview() }
        nodeViews.removeAll()
        canvas.layer.sublayers?.removeAll()
        connectionsDrawn = false
        canvasHeight = max(500, 150 + CGFloat(modes.count) * 108)
        canvasHeightConstraint?.constant = canvasHeight
        scrollView.setContentOffset(.zero, animated: false)
        modeStatusLabel.text = modes.isEmpty ? "No hay modos disponibles" : "\(modes.count) modos disponibles"
        syncButton.setTitle("↻  Actualizar configuración", for: .normal)
        buildNodes(selected: selected)
        setNeedsLayout()
    }

    func setSyncState(_ text: String, syncing: Bool = false) {
        modeStatusLabel.text = text
        syncButton.isEnabled = !syncing
        syncButton.setTitle(syncing ? "Actualizando…" : "↻  Actualizar configuración", for: .normal)
    }

    private func configure() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        let eyebrow = UILabel()
        eyebrow.text = "02 — CONFIGURACIÓN"
        eyebrow.font = .systemFont(ofSize: 11, weight: .heavy)
        eyebrow.textColor = AppTheme.accent

        let title = UILabel()
        title.text = "Elige tu modo"
        title.font = AppTheme.titleFont(24)
        title.textColor = AppTheme.primaryText

        let subtitle = UILabel()
        subtitle.text = "Toca un nodo para avanzar por el mapa."
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = AppTheme.secondaryText

        // El aviso de scroll vive AQUI, pegado al titulo, no solo flotando
        // abajo — asi se ve desde el primer momento, antes de que alguien
        // ya haya intentado deslizar y se confunda.
        scrollHint.text = "▾ desliza hacia abajo para ver más modos"
        scrollHint.font = .systemFont(ofSize: 10.5, weight: .semibold)
        scrollHint.textColor = AppTheme.accent
        scrollHint.textAlignment = .center
        scrollHint.alpha = 0

        modeStatusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        modeStatusLabel.textColor = AppTheme.secondaryText
        modeStatusLabel.textAlignment = .center
        modeStatusLabel.text = "Sincronizando modos..."
        syncButton.setTitle("↻  Actualizar configuración", for: .normal)
        syncButton.setTitleColor(AppTheme.accent, for: .normal)
        syncButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        syncButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [eyebrow, title, subtitle, modeStatusLabel, syncButton, scrollHint])
        headerStack.axis = .vertical
        headerStack.spacing = 4
        headerStack.setCustomSpacing(8, after: subtitle)
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
		scrollView.alwaysBounceVertical = true
		scrollView.isScrollEnabled = true
        canvas.translatesAutoresizingMaskIntoConstraints = false

        addSubview(headerStack)
        addSubview(scrollView)
        scrollView.addSubview(canvas)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            headerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            headerStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Patron oficial de Apple para contenido scrollable con Auto Layout:
            // las 4 esquinas del contenido van al contentLayoutGuide (define el
            // tamano REAL scrolleable), y el ancho va al frameLayoutGuide (el
            // viewport visible) — asi no hay ambiguedad de constraints, a
            // diferencia del intento anterior que pineaba directo a scrollView.
            canvas.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            canvas.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            canvas.heightAnchor.constraint(equalToConstant: canvasHeight)
        ])
        canvasHeightConstraint = canvas.constraints.first { $0.firstAttribute == .height }
        scrollView.delegate = self
    }

    @objc private func refreshTapped() {
        delegate?.missionMapViewDidRequestRefresh(self)
    }

    /// Muestra "desliza para ver mas" solo si de verdad hay contenido oculto
    /// abajo, y lo desvanece en cuanto el usuario ya hizo scroll.
    private func updateScrollHint() {
        let hasMoreBelow = scrollView.contentSize.height > scrollView.bounds.height + 4
        let alreadyScrolled = scrollView.contentOffset.y > 12
        UIView.animate(withDuration: 0.2) {
            self.scrollHint.alpha = (hasMoreBelow && !alreadyScrolled) ? 1 : 0
        }
    }

    private func buildNodes(selected: DavizinMode?) {
        for (index, mode) in modes.enumerated() {
            let node = MissionNodeView(mode: mode, index: index)
            node.onTap = { [weak self] in self?.selectNode(at: index) }
            if let selected = selected, selected.id == mode.id {
                node.setSelected(true)
            }
            canvas.addSubview(node)
            nodeViews.append(node)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = canvas.bounds.width > 0 ? canvas.bounds.width : bounds.width
        guard w > 0, !nodeViews.isEmpty else { return }
        let positions = generatePositions(count: nodeViews.count)
        for (index, node) in nodeViews.enumerated() {
            let pos = positions[index]
            let size: CGFloat = 74
            node.frame = CGRect(x: pos.x * w - size / 2, y: pos.y * canvasHeight, width: size, height: size)
        }
        if !connectionsDrawn && nodeViews.allSatisfy({ $0.frame != .zero }) {
            connectionsDrawn = true
            drawConnections()
        }
        updateScrollHint()
    }

    private func drawConnections() {
        guard nodeViews.count > 1 else { return }
        let container = CALayer()
        container.frame = canvas.bounds

        for i in 0..<(nodeViews.count - 1) {
            let start = nodeViews[i].center
            let end = nodeViews[i + 1].center
            let path = UIBezierPath()
            path.move(to: start)
            let control = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 30)
            path.addQuadCurve(to: end, controlPoint: control)

            let track = CAShapeLayer()
            track.path = path.cgPath
            track.strokeColor = AppTheme.hairlineStrong.cgColor
            track.fillColor = UIColor.clear.cgColor
            track.lineWidth = 2
            track.lineDashPattern = [3, 9]
            container.addSublayer(track)

            let flow = CAShapeLayer()
            flow.path = path.cgPath
            flow.strokeColor = AppTheme.accent.cgColor
            flow.fillColor = UIColor.clear.cgColor
            flow.lineWidth = 2
            flow.lineDashPattern = [3, 9]
            flow.opacity = 0.65
            flow.shadowColor = AppTheme.accent.cgColor
            flow.shadowRadius = 4
            flow.shadowOpacity = 0.8
            flow.shadowOffset = .zero
            container.addSublayer(flow)

            let dashAnim = CABasicAnimation(keyPath: "lineDashPhase")
            dashAnim.fromValue = 0
            dashAnim.toValue = -24
            dashAnim.duration = 1.4
            dashAnim.repeatCount = .infinity
            flow.add(dashAnim, forKey: "flow")

            let particle = CALayer()
            particle.backgroundColor = AppTheme.accentHot.cgColor
            particle.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
            particle.cornerRadius = 2.5
            particle.shadowColor = AppTheme.accentHot.cgColor
            particle.shadowRadius = 6
            particle.shadowOpacity = 1
            particle.shadowOffset = .zero
            container.addSublayer(particle)

            let travel = CAKeyframeAnimation(keyPath: "position")
            travel.path = path.cgPath
            travel.duration = 2.6
            travel.repeatCount = .infinity
            travel.beginTime = CACurrentMediaTime() + Double(i) * 0.5
            particle.add(travel, forKey: "travel")
        }
        canvas.layer.insertSublayer(container, at: 0)

        for node in nodeViews {
            node.startBreathing()
        }
    }

    private func selectNode(at index: Int) {
        SoundService.shared.playClick()
        nodeViews.forEach { $0.setSelected(false) }
        nodeViews[index].setSelected(true)
        let mode = modes[index]
        modeStatusLabel.text = "Modo \(index + 1) de \(modes.count) • \(mode.displayName)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.delegate?.missionMapView(self, didSelect: mode)
        }
    }
}

// MARK: - Nodo individual del mapa

final class MissionNodeView: UIView {
    var onTap: (() -> Void)?
    private let mode: DavizinMode
    private let glyphLabel = UILabel()
    private let nameLabel = UILabel()

    init(mode: DavizinMode, index: Int) {
        self.mode = mode
        super.init(frame: .zero)
        backgroundColor = AppTheme.card
        layer.cornerRadius = 37
        layer.borderWidth = 2.5
        layer.borderColor = AppTheme.hairlineStrong.cgColor
        isUserInteractionEnabled = true

        glyphLabel.text = mode.symbol
        glyphLabel.font = .systemFont(ofSize: 20)
        glyphLabel.textColor = AppTheme.primaryText
        glyphLabel.textAlignment = .center

        nameLabel.text = mode.displayName
        nameLabel.font = .systemFont(ofSize: 10.5, weight: .heavy)
        nameLabel.textColor = AppTheme.primaryText
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [glyphLabel, nameLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)

        alpha = 0
        transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.45, delay: Double(index) * 0.08, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3, options: [.curveEaseOut]) {
            self.alpha = 1
            self.transform = .identity
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() {
        UIView.animate(withDuration: 0.1, animations: { self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }) { _ in
            UIView.animate(withDuration: 0.1) { self.transform = .identity }
        }
        onTap?()
    }

    func setSelected(_ selected: Bool) {
        UIView.animate(withDuration: 0.25) {
            self.layer.borderColor = (selected ? AppTheme.accent : AppTheme.hairlineStrong).cgColor
            self.layer.shadowColor = AppTheme.accent.cgColor
            self.layer.shadowOpacity = selected ? 0.4 : 0
            self.layer.shadowRadius = 20
            self.layer.shadowOffset = .zero
        }
    }

    func startBreathing() {
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = 0.0
        pulse.toValue = 0.18
        pulse.duration = 1.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.beginTime = CACurrentMediaTime() + 0.8
        layer.shadowColor = AppTheme.accent.cgColor
        layer.shadowRadius = 14
        layer.shadowOffset = .zero
        layer.add(pulse, forKey: "breathe")
    }
}

private extension DavizinMode {
    var symbol: String {
        return "▸"
    }
}

extension MissionMapView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateScrollHint()
    }
}
