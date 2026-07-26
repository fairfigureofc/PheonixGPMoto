import Foundation

struct E87Frame: Sendable {
    let flag: UInt8
    let command: UInt8
    let body: Data
}

enum E87Codec {
    static let chunkSize = 490

    static func frame(flag: UInt8, command: UInt8, body: Data) -> Data {
        var result = Data([0xFE, 0xDC, 0xBA, flag, command])
        result.append(UInt8((body.count >> 8) & 0xFF))
        result.append(UInt8(body.count & 0xFF))
        result.append(body)
        result.append(0xEF)
        return result
    }

    static func parse(_ data: Data) -> E87Frame? {
        guard data.count >= 8,
              data[0] == 0xFE, data[1] == 0xDC, data[2] == 0xBA,
              data[data.count - 1] == 0xEF else { return nil }
        let length = Int(data[5]) << 8 | Int(data[6])
        guard data.count == length + 8 else { return nil }
        return E87Frame(flag: data[3], command: data[4], body: data.subdata(in: 7 ..< (7 + length)))
    }

    static func crc16Xmodem(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0 ..< 8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    static func metadata(sequence: UInt8, file: Data, name: String) -> Data {
        let crc = crc16Xmodem(file)
        var body = Data([sequence])
        let size = UInt32(file.count)
        body.append(contentsOf: [UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
        body.append(contentsOf: [UInt8(crc >> 8), UInt8(crc & 0xFF), UInt8.random(in: .min ... .max), UInt8.random(in: .min ... .max)])
        body.append(name.data(using: .ascii) ?? Data())
        body.append(0)
        return body
    }

    static func dataChunk(sequence: UInt8, slot: UInt8, payload: Data) -> Data {
        let crc = crc16Xmodem(payload)
        var body = Data([sequence, 0x1D, slot, UInt8(crc >> 8), UInt8(crc & 0xFF)])
        body.append(payload)
        return frame(flag: 0x80, command: 0x01, body: body)
    }
}

enum E87Error: LocalizedError {
    case bluetoothUnavailable
    case notConnected
    case characteristicsMissing
    case authenticationFailed
    case timeout(String)
    case deviceRejected(UInt8)
    case jpegEncodingFailed
    case benchmarkStopped

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable: "Bluetooth is unavailable."
        case .notConnected: "The badge is not connected."
        case .characteristicsMissing: "Required E87 characteristics were not found."
        case .authenticationFailed: "Jieli authentication failed."
        case let .timeout(step): "Timed out waiting for \(step)."
        case let .deviceRejected(status): "Badge rejected the upload (status 0x\(String(status, radix: 16)))."
        case .jpegEncodingFailed: "Could not encode the test image."
        case .benchmarkStopped: "Benchmark stopped."
        }
    }
}
