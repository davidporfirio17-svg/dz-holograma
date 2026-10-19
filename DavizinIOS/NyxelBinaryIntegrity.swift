import Foundation
import CryptoKit
import MachO

/// Verificación de integridad del binario propio.
///
/// Al arrancar y antes de operaciones críticas, hasheamos el segmento `__TEXT`
/// del Mach-O del app y comparamos contra un valor "esperado". Si re-firman la
/// IPA o modifican bytes del código, el hash cambia y lo detectamos.
///
/// El valor esperado NO se guarda como un string literal al que un atacante pueda
/// hacer `grep`. Se construye en runtime mediante una fórmula que combina
/// constantes dispersas, de modo que parchear el chequeo requiere también
/// recalcular y reemplazar la fórmula.
enum NyxelBinaryIntegrity {

    /// Resultado del chequeo. `.unknown` cuando no se pudo medir (p.ej. no se
    /// localizó el segmento) — tratarlo como "no bloquear" para no romper
    /// usuarios legítimos ante casos raros.
    enum Verdict {
        case match
        case mismatch
        case unknown
    }

    /// Hash SHA-256 del segmento __TEXT en hex. Devuelve nil si no se puede medir.
    /// El main executable es la imagen con índice 0 en el image list de dyld.
    static func textSegmentDigest() -> String? {
        guard _dyld_image_count() > 0 else { return nil }
        guard let header = _dyld_get_image_header(0) else { return nil }
        let slide = _dyld_get_image_vmaddr_slide(0)
        return sha256OfTextSegment(header: header, slide: slide)
    }

    /// Chequeo contra un valor esperado. Si el proyecto no provee uno (durante
    /// desarrollo), devuelve `.unknown`.
    static func verify() -> Verdict {
        guard let actual = textSegmentDigest() else { return .unknown }
        guard let expected = expectedDigest(), !expected.isEmpty else { return .unknown }
        return actual.caseInsensitiveCompare(expected) == .orderedSame ? .match : .mismatch
    }

    // MARK: - Internals

    private static func sha256OfTextSegment(header: UnsafePointer<mach_header>, slide: Int) -> String? {
        let is64 = header.pointee.magic == MH_MAGIC_64 || header.pointee.magic == MH_CIGAM_64
        guard is64 else { return nil }
        let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        let ncmds = Int(header64.pointee.ncmds)
        var cursor = UnsafeRawPointer(header64).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<ncmds {
            let cmd = cursor.assumingMemoryBound(to: load_command.self).pointee
            if cmd.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self).pointee
                let name = withUnsafePointer(to: seg.segname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
                }
                if name == "__TEXT" {
                    let base = UnsafeRawPointer(bitPattern: Int(seg.vmaddr) + slide)
                    guard let base else { return nil }
                    let data = Data(bytes: base, count: Int(seg.vmsize))
                    let digest = SHA256.hash(data: data)
                    return digest.map { String(format: "%02x", $0) }.joined()
                }
            }
            cursor = cursor.advanced(by: Int(cmd.cmdsize))
        }
        return nil
    }

    /// Hash esperado. Hoy devuelve nil (modo "medir, no bloquear") — en una build
    /// de release, poblar con el hash de ESA build específica para que un re-sign
    /// se detecte. La fórmula debería construir el string a partir de varias
    /// constantes para no dejarlo como un literal grep-eable.
    private static func expectedDigest() -> String? {
        // TODO: en release, generar el hash del __TEXT del build final y
        // embebrlo aquí descompuesto en varios UInt32 que se recombinan en
        // runtime. Mientras tanto, el chequeo solo mide y registra.
        return nil
    }
}
