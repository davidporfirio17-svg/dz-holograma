import Foundation
import Network
import UIKit

/// Chequeo previo para operaciones AirLift.
///
/// iOS 27 (y 26 en el fondo) con datos celulares activos ignora las rutas /32
/// del Packet Tunnel y escoge siempre la interfaz celular como ruta default.
/// El workaround oficial del ecosistema (StikJIT, LocalDevVPN, StikDebug,
/// SideStore) es: conectar el VPN primero y luego activar **Modo Avión**.
/// Con Modo Avión la interfaz celular queda abajo, el VPN loopback sigue
/// arriba (es local, no depende de internet) y la utun pasa a ser la única
/// ruta para 10.7.0.x — entonces `remotepairingd` recibe pair-verify con
/// source IP correcto y acepta.
enum NyxelCellularPreflight {
    enum NetState {
        case ok                 // WiFi activo, o Airplane Mode con VPN — se puede operar
        case cellularOnly       // Solo datos celulares, sin WiFi, sin Airplane — hay que avisar
        case noNetwork          // Ni cellular ni WiFi ni Airplane+VPN — nada que hacer
    }

    /// Mide el estado de red actual. Síncrono con timeout de 1s.
    static func currentState(timeout: TimeInterval = 1.0) -> NetState {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var result: NetState = .noNetwork
        monitor.pathUpdateHandler = { path in
            let wifi = path.usesInterfaceType(.wifi)
            let cellular = path.usesInterfaceType(.cellular)
            let hasOther = path.availableInterfaces.contains { $0.type == .other }
            // Airplane mode: el path no toca cellular ni wifi pero el VPN (utun = .other) sigue arriba.
            let airplaneWithVpn = !cellular && !wifi && hasOther && path.status != .unsatisfied
            if wifi || airplaneWithVpn {
                result = .ok
            } else if cellular {
                result = .cellularOnly
            } else {
                result = .noNetwork
            }
            semaphore.signal()
        }
        monitor.start(queue: DispatchQueue.global(qos: .userInitiated))
        _ = semaphore.wait(timeout: .now() + timeout)
        monitor.cancel()
        return result
    }

    /// Muestra una alerta explicando el procedimiento de Modo Avión.
    /// Llama `onContinue` cuando el usuario toca "Ya lo activé, continuar".
    static func presentAirplaneModeGuide(from presenter: UIViewController,
                                         onContinue: @escaping () -> Void,
                                         onCancel: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Operar con datos celulares",
            message: """
                iOS no permite enrutar la operación por la red local cuando los \
                datos celulares están activos. Para continuar:

                1. Mantén el VPN de Nyxel conectado.
                2. Activa **Modo Avión** desde el Centro de Control.
                3. Vuelve a esta pantalla y toca "Continuar".

                Durante la operación tu internet queda pausado por ser Modo \
                Avión, pero la app sigue trabajando porque solo usa la red \
                local. Al terminar, apaga Modo Avión y recuperas tus datos.
                """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in onCancel() })
        alert.addAction(UIAlertAction(title: "Continuar", style: .default) { _ in onContinue() })
        presenter.present(alert, animated: true)
    }
}
