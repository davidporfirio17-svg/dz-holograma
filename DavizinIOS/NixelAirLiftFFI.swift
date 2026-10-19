import Foundation

/// Primera capa del backend AirLift: crea el registro criptográfico RPairing
/// que luego consume tunnel_create_rppairing. No inicia el túnel ni marca pairing.
enum NixelAirLiftFFI {
    enum Error: LocalizedError {
        case unavailable
        case generationFailed
        case serializationFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "El backend idevice-ffi no está enlazado en esta compilación."
            case .generationFailed:
                return "No se pudo generar el registro RPairing."
            case .serializationFailed:
                return "No se pudo serializar el registro RPairing."
            }
        }
    }

    static func preparePairingRecord(hostname: String) throws -> Data {
        guard !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.generationFailed
        }

        var handle: UnsafeMutableRawPointer?
        let generateError = hostname.withCString { name in
            rp_pairing_file_generate(name, &handle)
        }
        guard generateError == nil, let handle else {
            throw Error.generationFailed
        }
        defer { rp_pairing_file_free(handle) }

        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        let serializeError = rp_pairing_file_to_bytes(handle, &bytes, &length)
        guard serializeError == nil, let bytes, length > 0 else {
            throw Error.serializationFailed
        }
        defer { idevice_data_free(bytes, length) }
        return Data(bytes: bytes, count: length)
    }
}
