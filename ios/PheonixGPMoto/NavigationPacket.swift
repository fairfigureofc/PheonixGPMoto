import Foundation

struct NavigationPacket {
    enum Maneuver: UInt8, CaseIterable, Identifiable {
        case straight = 0
        case left = 1
        case right = 2

        var id: Self {
            self
        }

        var label: String {
            switch self {
            case .straight: "Straight"
            case .left: "Left"
            case .right: "Right"
            }
        }
    }

    static let byteCount = 64

    var sequence: UInt16
    var maneuver: Maneuver
    var lightMode: Bool
    var distanceToTurnMeters: UInt32
    var remainingMeters: UInt32
    var remainingSeconds: UInt32
    var roadName: String

    func encoded() -> Data {
        var data = Data(capacity: Self.byteCount)
        data.append(1) // Protocol version
        data.appendLittleEndian(sequence)
        data.append(maneuver.rawValue)
        data.append(lightMode ? 1 : 0)
        data.appendLittleEndian(distanceToTurnMeters)
        data.appendLittleEndian(remainingMeters)
        data.appendLittleEndian(remainingSeconds)

        let roadBytes = Data(roadName.uppercased().utf8.prefix(46))
        data.append(UInt8(roadBytes.count))
        data.append(roadBytes)
        if data.count < Self.byteCount {
            data.append(Data(repeating: 0, count: Self.byteCount - data.count))
        }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
