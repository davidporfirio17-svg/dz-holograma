import Foundation
import Darwin
import MachO

/// Capa de defensa anti-tampering 100% local.
///
/// Objetivo: dificultar que alguien baje la IPA, le quite el check de Key y
/// la revenda. Se complementa con `NyxelBinaryIntegrity` y `NyxelKeyEntanglement`.
///
/// Importante: ninguna de estas defensas es infalible por sí sola. El valor viene
/// de **combinarlas** y de que varias degradan silenciosamente en lugar de
/// mostrar un error claro al atacante.
enum NyxelAntiTamper {

    /// Resultado de una verificación. `.pass` significa entorno confiable;
    /// `.suspect(reason)` significa que hay señales de debugger/hook/parcheo.
    enum Verdict {
        case pass
        case suspect(String)

        var isSuspect: Bool { if case .suspect = self { return true } else { return false } }
    }

    /// Ejecuta todas las verificaciones y devuelve el peor veredicto.
    /// Pensado para llamarse al arrancar la app y antes de operaciones críticas.
    static func inspect() -> Verdict {
        if isBeingDebugged() { return .suspect("DBG-001") }
        if hasFridaSignature() { return .suspect("DBG-002") }
        if hasSuspiciousDyldImages() { return .suspect("DBG-003") }
        return .pass
    }

    /// Llama a `ptrace(PT_DENY_ATTACH)` para que iOS no permita engancharle un
    /// debugger. Debe llamarse LO ANTES POSIBLE en el ciclo de vida del app
    /// (dentro de `AppDelegate.application(_:didFinishLaunchingWithOptions:)`).
    static func denyPtraceAttach() {
        typealias PtraceFn = @convention(c) (Int32, pid_t, UnsafeMutableRawPointer?, Int32) -> Int32
        let PT_DENY_ATTACH: Int32 = 31
        let handle = dlopen(nil, RTLD_NOW)
        if let sym = dlsym(handle, "ptrace") {
            let ptraceFn = unsafeBitCast(sym, to: PtraceFn.self)
            _ = ptraceFn(PT_DENY_ATTACH, 0, nil, 0)
        }
    }

    // MARK: - Verificaciones individuales

    /// Detecta debugger vía `sysctl` (técnica estándar en iOS, documentada en
    /// Apple Technical Q&A 1361). `P_TRACED` = 0x00000800 (de `<sys/proc.h>`).
    private static func isBeingDebugged() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.size
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        if junk != 0 { return false }
        let P_TRACED: Int32 = 0x00000800
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// Busca el puerto por defecto de Frida (27042) abierto en loopback.
    private static func hasFridaSignature() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(27042).bigEndian
        addr.sin_addr.s_addr = UInt32(0x7F000001).bigEndian
        let r = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
                connect(fd, sap, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    /// Enumera las imágenes cargadas por dyld y busca strings asociados a
    /// frameworks de hooking típicos.
    private static func hasSuspiciousDyldImages() -> Bool {
        let needles = ["FridaGadget", "frida", "cynject", "libcycript", "SubstrateLoader", "MobileSubstrate", "SubstrateInserter"]
        let count = _dyld_image_count()
        for i in 0..<count {
            guard let raw = _dyld_get_image_name(i) else { continue }
            let name = String(cString: raw).lowercased()
            if needles.contains(where: { name.contains($0.lowercased()) }) {
                return true
            }
        }
        return false
    }
}
