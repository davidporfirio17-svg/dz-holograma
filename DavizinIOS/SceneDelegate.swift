import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var bridge: DavizinBridge?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)

        // 1. Splash de marca (anillo dibujandose) — se muestra siempre al abrir.
        let splash = SplashViewController()
        splash.modalPresentationStyle = .fullScreen
        splash.onFinished = { [weak self] in
            self?.showMainApp(in: window)
        }

        window.rootViewController = splash
        self.window = window
        window.makeKeyAndVisible()
    }

    /// 2. Flujo principal real: login -> entorno -> mapa de mision -> operacion.
    /// El aviso real (si el Worker tiene uno publicado en /anuncio) SI se
    /// muestra, pero justo despues de validar la key — eso ya lo hace
    /// DavizinBridge, porque el /check del Worker exige key+hwid: no existe
    /// forma de consultar un aviso antes de que la persona escriba su key.
    private func showMainApp(in window: UIWindow) {
        // Log compatibility status before proceeding
        let compatStatus = NyxelSupportPolicy.status.label
        nyxelLog("Scene loading: Compatibility status = \(compatStatus)", level: "INFO")
        
        let rootViewController = ViewController()
        rootViewController.modalPresentationStyle = .fullScreen

        let bridge = DavizinBridge()
        bridge.connect(to: rootViewController)
        self.bridge = bridge

        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.rootViewController = rootViewController
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
}
