import Foundation

/// Canal de archivos con permisos elevados hacia el contenedor de otra app,
/// usando el registro de pairing ya guardado (fase 1) y el túnel RSD de
/// AirLift (fase 2 — house_arrest/AFC). Es un camino ALTERNATIVO: cuando no
/// hay un registro de pairing guardado, no se usa y el llamador debe seguir
/// con su método normal.
enum NixelAirLiftFileChannel {
    struct ChannelError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// true solo si hay un registro de pairing guardado ("2424" es la clave
    /// fija que usa NixelPairingSession al completar la fase 1).
    static var isAvailable: Bool {
        NixelPairingRecordStore.shared.load(deviceID: "2424") != nil
    }

    static func write(_ data: Data, toRelativePath relativePath: String, bundleID: String, discoverTimeout: TimeInterval = 20) -> Result<Void, ChannelError> {
        guard let record = NixelPairingRecordStore.shared.load(deviceID: "2424") else {
            return .failure(ChannelError(message: "No hay un registro de pairing guardado."))
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = record.withUnsafeBytes { recordBuf -> Int32 in
            guard let recordBase = recordBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return data.withUnsafeBytes { dataBuf -> Int32 in
                let dataBase = dataBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return bundleID.withCString { bid in
                    relativePath.withCString { path in
                        nyxel_airlift_container_io(
                            recordBase, record.count,
                            bid, path,
                            1,
                            dataBase, data.count,
                            nil, nil,
                            discoverTimeout,
                            &errorPointer
                        )
                    }
                }
            }
        }
        if status == 0 { return .success(()) }
        let message = errorPointer.map { String(cString: $0) } ?? "Error desconocido del canal AirLift (\(status))."
        if let errorPointer { nyxel_free_string(errorPointer) }
        return .failure(ChannelError(message: message))
    }

    static func read(relativePath: String, bundleID: String, discoverTimeout: TimeInterval = 20) -> Result<Data, ChannelError> {
        guard let record = NixelPairingRecordStore.shared.load(deviceID: "2424") else {
            return .failure(ChannelError(message: "No hay un registro de pairing guardado."))
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        var outData: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let status = record.withUnsafeBytes { recordBuf -> Int32 in
            guard let recordBase = recordBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return bundleID.withCString { bid in
                relativePath.withCString { path in
                    nyxel_airlift_container_io(
                        recordBase, record.count,
                        bid, path,
                        0,
                        nil, 0,
                        &outData, &outLen,
                        discoverTimeout,
                        &errorPointer
                    )
                }
            }
        }
        if status == 0, let outData {
            let data = Data(bytes: outData, count: outLen)
            nyxel_free_data(outData, outLen)
            return .success(data)
        }
        let message = errorPointer.map { String(cString: $0) } ?? "Error desconocido del canal AirLift (\(status))."
        if let errorPointer { nyxel_free_string(errorPointer) }
        return .failure(ChannelError(message: message))
    }
}
