import UIKit

final class DavizinAnimatedBackgroundView: UIView {

    // ── Nodo flotante ─────────────────────────────────────────────
    private struct Node {
        var x, y: CGFloat          // posición actual (0–1 normalizado)
        var vx, vy: CGFloat         // velocidad
        var phase: CGFloat          // fase para pulso
        var size: CGFloat           // tamaño del punto
        var colorIndex: Int         // color (0=cyan, 1=blue, 2=purple)
    }

    // ── Config ────────────────────────────────────────────────────
    private let nodeCount        = 55
    private let connectionDist   = CGFloat(0.30)   // distancia máxima para conectar
    private let baseSpeed        = CGFloat(0.00018) // velocidad base
    private let pulseSpeed       = CGFloat(0.04)    // velocidad de pulso
    private let dotMinSize       = CGFloat(2.5)
    private let dotMaxSize       = CGFloat(5.5)

    // ── State ─────────────────────────────────────────────────────
    private var nodes: [Node] = []
    private var displayLink: CADisplayLink?
    private var elapsed: CGFloat = 0

    // ── Paleta electric galaxy ──────────────────────────────────────
    private let colors: [UIColor] = [
        UIColor(red: 0.0, green: 0.784, blue: 1.0, alpha: 1),   // #00C8FF azul eléctrico
        UIColor(red: 0.0, green: 0.42, blue: 0.90, alpha: 1),   // #006BE6 azul profundo
        UIColor(red: 0.42, green: 0.20, blue: 1.0, alpha: 1),   // #6B33FF violeta galaxia
        UIColor(white: 1.0, alpha: 1)                            // blanco puro (estrella)
    ]

    // ── Init ──────────────────────────────────────────────────────
    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    deinit { displayLink?.invalidate() }

    private func setup() {
        backgroundColor = AppTheme.background
        isUserInteractionEnabled = false
        layer.masksToBounds = true
        buildNodes()
    }

    private func buildNodes() {
        nodes = (0..<nodeCount).map { _ in
            Node(
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                vx: CGFloat.random(in: -1...1) * baseSpeed,
                vy: CGFloat.random(in: -1...1) * baseSpeed,
                phase: CGFloat.random(in: 0...(2 * .pi)),
                size: CGFloat.random(in: dotMinSize...dotMaxSize),
                colorIndex: Int.random(in: 0..<colors.count)
            )
        }
    }

    // ── Display link ─────────────────────────────────────────────
    func startAnimating() {
        guard displayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(tick(_:)))
        dl.preferredFramesPerSecond = 60
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopAnimating() : startAnimating()
    }

    @objc private func tick(_ dl: CADisplayLink) {
        elapsed += CGFloat(dl.duration)
        updateNodes()
        setNeedsDisplay()
    }

    private func updateNodes() {
        for i in nodes.indices {
            // Mover
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy

            // Rebotar en los bordes con algo de variación
            if nodes[i].x < 0 || nodes[i].x > 1 {
                nodes[i].vx *= -1
                nodes[i].vx += CGFloat.random(in: -0.00002...0.00002)
                nodes[i].x = max(0, min(1, nodes[i].x))
            }
            if nodes[i].y < 0 || nodes[i].y > 1 {
                nodes[i].vy *= -1
                nodes[i].vy += CGFloat.random(in: -0.00002...0.00002)
                nodes[i].y = max(0, min(1, nodes[i].y))
            }

            // Mantener velocidad en rango
            let maxSpeed = baseSpeed * 3
            let speed = sqrt(nodes[i].vx * nodes[i].vx + nodes[i].vy * nodes[i].vy)
            if speed > maxSpeed {
                nodes[i].vx = nodes[i].vx / speed * maxSpeed
                nodes[i].vy = nodes[i].vy / speed * maxSpeed
            }
            if speed < baseSpeed * 0.3 {
                nodes[i].vx += CGFloat.random(in: -baseSpeed...baseSpeed)
                nodes[i].vy += CGFloat.random(in: -baseSpeed...baseSpeed)
            }

            // Avanzar fase de pulso
            nodes[i].phase += pulseSpeed
        }
    }

    // ── Drawing ───────────────────────────────────────────────────
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width, h = rect.height

        // Convertir nodos a coordenadas de pantalla
        let pts = nodes.map { CGPoint(x: $0.x * w, y: $0.y * h) }

        // Dibujar conexiones
        for i in 0..<nodes.count {
            for j in (i+1)..<nodes.count {
                let dx = nodes[i].x - nodes[j].x
                let dy = nodes[i].y - nodes[j].y
                let dist = sqrt(dx*dx + dy*dy)
                guard dist < connectionDist else { continue }

                let alpha = (1 - dist / connectionDist) * 0.5
                let pulse = (sin(nodes[i].phase * 0.5) + 1) * 0.5
                let finalAlpha = alpha * (0.3 + pulse * 0.4)

                // Color de la línea mezclando los dos nodos
                let c1 = colors[nodes[i].colorIndex]
                let c2 = colors[nodes[j].colorIndex]
                let blended = blend(c1, c2, t: 0.5).withAlphaComponent(finalAlpha)

                ctx.setStrokeColor(blended.cgColor)
                ctx.setLineWidth(0.6 + pulse * 0.6)
                ctx.move(to: pts[i])
                ctx.addLine(to: pts[j])
                ctx.strokePath()
            }
        }

        // Dibujar puntos (con glow)
        for i in 0..<nodes.count {
            let pulse = (sin(nodes[i].phase) + 1) * 0.5
            let size = nodes[i].size * (0.7 + pulse * 0.6)
            let color = colors[nodes[i].colorIndex]
            let alpha = 0.5 + pulse * 0.5
            let p = pts[i]

            // Glow exterior
            ctx.setFillColor(color.withAlphaComponent(alpha * 0.15).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - size*2, y: p.y - size*2, width: size*4, height: size*4))

            // Glow medio
            ctx.setFillColor(color.withAlphaComponent(alpha * 0.25).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - size*1.3, y: p.y - size*1.3, width: size*2.6, height: size*2.6))

            // Punto central
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - size/2, y: p.y - size/2, width: size, height: size))
        }

        // Ondas expansivas ocasionales
        let waveT = elapsed.truncatingRemainder(dividingBy: 4.0) / 4.0
        if waveT < 0.7 {
            let waveR = waveT * max(w, h) * 0.8
            let waveAlpha = (1 - waveT / 0.7) * 0.06
            let waveX = w * 0.5, waveY = h * 0.4
            let waveColor = UIColor(red: 0.0, green: 0.784, blue: 1.0, alpha: waveAlpha)
            ctx.setStrokeColor(waveColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: waveX - waveR, y: waveY - waveR, width: waveR*2, height: waveR*2))
        }
    }

    // ── Helper ────────────────────────────────────────────────────
    private func blend(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1*(1-t)+r2*t, green: g1*(1-t)+g2*t, blue: b1*(1-t)+b2*t, alpha: 1)
    }
}
