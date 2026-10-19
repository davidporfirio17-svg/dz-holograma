import UIKit

// MARK: - NoticeViewController — aviso publicado desde el Worker, antes del login.
// Solo se muestra si hay un aviso activo. El fetch real va contra un endpoint
// publico (sin key) de tu Worker, ej: GET https://dz-holograma.davidporfirio17.workers.dev/notice
// que responde { "hasNotice": bool, "title": string, "message": string }.

struct RemoteNotice {
    let title: String
    let message: String
}

enum NoticeService {
    /// Reemplazar con una llamada real a tu Worker. Por ahora regresa nil
    /// (sin aviso) para que el flujo entre directo al login por default.
    static func fetchActiveNotice(completion: @escaping (RemoteNotice?) -> Void) {
        // Ejemplo real:
        // URLSession.shared.dataTask(with: URL(string: "https://dz-holograma.davidporfirio17.workers.dev/notice")!) { data, _, _ in
        //     guard let data = data,
        //           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        //           json["hasNotice"] as? Bool == true else { completion(nil); return }
        //     completion(RemoteNotice(title: json["title"] as? String ?? "", message: json["message"] as? String ?? ""))
        // }.resume()
        completion(nil)
    }
}

final class NoticeViewController: UIViewController {
    var onContinue: (() -> Void)?
    private let notice: RemoteNotice

    init(notice: RemoteNotice) {
        self.notice = notice
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppTheme.background

        let eyebrow = UILabel()
        eyebrow.text = "◉ AVISO"
        eyebrow.font = .systemFont(ofSize: 10, weight: .heavy)
        eyebrow.textColor = AppTheme.accent

        let card = UIView()
        card.backgroundColor = AppTheme.card
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = AppTheme.hairlineStrong.cgColor

        let accentBar = UIView()
        accentBar.backgroundColor = AppTheme.accent
        accentBar.layer.shadowColor = AppTheme.accent.cgColor
        accentBar.layer.shadowRadius = 6
        accentBar.layer.shadowOpacity = 0.8
        accentBar.layer.shadowOffset = .zero

        let titleLabel = UILabel()
        titleLabel.text = notice.title
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = AppTheme.primaryText
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = notice.message
        messageLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        messageLabel.textColor = AppTheme.secondaryText
        messageLabel.numberOfLines = 0

        let continueButton = DavizinButton(title: "Entendido", style: .primary)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        [eyebrow, card, continueButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [accentBar, titleLabel, messageLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }

        NSLayoutConstraint.activate([
            eyebrow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            eyebrow.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -140),

            card.topAnchor.constraint(equalTo: eyebrow.bottomAnchor, constant: 14),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: AppTheme.contentMaximumWidth),

            accentBar.topAnchor.constraint(equalTo: card.topAnchor),
            accentBar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            accentBar.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            accentBar.heightAnchor.constraint(equalToConstant: 3),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            messageLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),

            continueButton.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 18),
            continueButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            continueButton.widthAnchor.constraint(equalToConstant: AppTheme.contentMaximumWidth),
            continueButton.heightAnchor.constraint(equalToConstant: AppTheme.controlHeight)
        ])
    }

    @objc private func continueTapped() {
        SoundService.shared.playClick()
        onContinue?()
    }
}
