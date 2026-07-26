import Combine
@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class E87BluetoothClient: NSObject, ObservableObject {
    @Published private(set) var state = "Bluetooth starting…"
    @Published private(set) var discovered: [CBPeripheral] = []
    @Published private(set) var isConnected = false
    @Published private(set) var logLines: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataWriter: CBCharacteristic?
    private var controlWriter: CBCharacteristic?
    private var notifications: [Data] = []
    private var connectedContinuation: CheckedContinuation<Void, Error>?
    private var discoveryContinuation: CheckedContinuation<Void, Error>?
    private var pendingNotificationUUIDs = Set<CBUUID>()
    private var initialized = false
    private var authenticated = false
    private var sequence: UInt8 = 1

    private let aeService = CBUUID(string: "AE00")
    private let fdService = CBUUID(string: "C2E6FD00-E966-1000-8000-BEF9C223DF6A")
    private let ae01 = CBUUID(string: "AE01")
    private let ae02 = CBUUID(string: "AE02")
    private let fd02 = CBUUID(string: "C2E6FD02-E966-1000-8000-BEF9C223DF6A")
    private let notifyUUIDs = Set([
        CBUUID(string: "C2E6FD01-E966-1000-8000-BEF9C223DF6A"),
        CBUUID(string: "C2E6FD03-E966-1000-8000-BEF9C223DF6A"),
        CBUUID(string: "C2E6FD05-E966-1000-8000-BEF9C223DF6A"),
    ])

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else {
            state = "Turn Bluetooth on."
            return
        }
        discovered.removeAll()
        state = "Scanning…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func connect(_ target: CBPeripheral) async throws {
        central.stopScan()
        peripheral = target
        target.delegate = self
        state = "Connecting to \(target.name ?? "badge")…"
        try await withCheckedThrowingContinuation { continuation in
            connectedContinuation = continuation
            central.connect(target)
        }
        try await withCheckedThrowingContinuation { continuation in
            discoveryContinuation = continuation
            target.discoverServices([aeService, fdService])
        }
        guard dataWriter != nil, controlWriter != nil else { throw E87Error.characteristicsMissing }
        try await authenticateAndInitialize()
        isConnected = true
        state = "Connected"
    }

    func disconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
    }

    func upload(jpeg: Data) async throws -> Double {
        guard isConnected, dataWriter != nil else { throw E87Error.notConnected }
        let started = ContinuousClock.now
        notifications.removeAll()

        var seq = sequence
        try writeFrame(flag: 0xC0, command: 0x21, body: Data([seq, 0]))
        seq &+= 1
        _ = try await waitFrame(command: 0x21, timeout: 3)

        try writeFrame(flag: 0xC0, command: 0x27, body: Data([seq, 0, 0, 0, 0, 2, 1]))
        seq &+= 1
        _ = try await waitFrame(command: 0x27, timeout: 3)

        let temporaryName = String(format: "%08x.tmp", UInt32.random(in: .min ... .max))
        try writeFrame(flag: 0xC0, command: 0x1B, body: E87Codec.metadata(sequence: seq, file: jpeg, name: temporaryName))
        seq &+= 1
        let metadataAck = try await waitFrame(command: 0x1B, timeout: 3)
        let chunkSize = metadataAck.body.count >= 4 ? Int(metadataAck.body[2]) << 8 | Int(metadataAck.body[3]) : E87Codec.chunkSize
        guard chunkSize > 0, chunkSize <= 4096 else { throw E87Error.deviceRejected(0xFF) }

        var current = try await waitFrame(command: 0x1D, timeout: 5)
        var completed = false
        while !completed {
            guard current.body.count >= 8 else { throw E87Error.deviceRejected(0xFE) }
            let status = current.body[1]
            guard status == 0 else { throw E87Error.deviceRejected(status) }
            let windowSize = Int(current.body[2]) << 8 | Int(current.body[3])
            let offset = Int(current.body[4]) << 24 | Int(current.body[5]) << 16 | Int(current.body[6]) << 8 | Int(current.body[7])
            var sent = 0
            var slot: UInt8 = 0
            while sent < windowSize, offset + sent < jpeg.count {
                let length = min(chunkSize, min(windowSize - sent, jpeg.count - offset - sent))
                let payload = jpeg.subdata(in: (offset + sent) ..< (offset + sent + length))
                try write(E87Codec.dataChunk(sequence: seq, slot: slot, payload: payload), to: dataWriter)
                seq &+= 1
                slot = (slot + 1) & 7
                sent += length
            }

            let next = try await waitFrame(commands: [0x1D, 0x20, 0x1C], timeout: 8)
            switch next.command {
            case 0x1D:
                current = next
            case 0x20:
                try respondToFileComplete(next)
                let close = try await waitFrame(command: 0x1C, timeout: 5)
                try finish(close)
                completed = true
            case 0x1C:
                try finish(next)
                completed = true
            default:
                break
            }
        }
        sequence = seq == 0 ? 1 : seq
        return (ContinuousClock.now - started).milliseconds
    }

    private func authenticateAndInitialize() async throws {
        if !authenticated {
            notifications.removeAll()
            try write(JieliAuth.randomRequest(), to: dataWriter)
            _ = try await waitRaw({ $0.count == 17 && $0[0] == 1 }, timeout: 3, label: "auth response")
            try write(Data([0x02, 0x70, 0x61, 0x73, 0x73]), to: dataWriter)
            let challenge = try await waitRaw({ $0.count == 17 && $0[0] == 0 }, timeout: 3, label: "auth challenge")
            try write(JieliAuth.encryptedResponse(to: challenge), to: dataWriter)
            _ = try await waitRaw({ $0 == Data([0x02, 0x70, 0x61, 0x73, 0x73]) }, timeout: 3, label: "auth confirmation")
            authenticated = true
            appendLog("Authentication succeeded")
        }
        guard !initialized else { return }
        try writeFrame(flag: 0xC0, command: 0x06, body: Data([0x02, 0x00, 0x01]))
        sequence = 1
        try sendClockAndHeartbeat()
        initialized = true
        appendLog("Persistent session initialized")
    }

    private func sendClockAndHeartbeat() throws {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        let year = parts.year ?? 2026
        let time = Data([0x9E, 0x45, 0x08, 0x02, 0x07, 0x00, UInt8(year & 0xFF), UInt8((year >> 8) & 0xFF), UInt8(parts.month ?? 1), UInt8(parts.day ?? 1), 0, UInt8(parts.hour ?? 0), UInt8(parts.minute ?? 0)])
        try write(time, to: controlWriter)
        try write(Data([0x9E, 0x20, 0x08, 0x16, 0x01, 0x00, 0x01]), to: controlWriter)
        try write(Data([0x9E, 0xB5, 0x0B, 0x29, 0x01, 0x00, 0x80]), to: controlWriter)
    }

    private func respondToFileComplete(_ frame: E87Frame) throws {
        let deviceSequence = frame.body.first ?? 0
        let path = "\\U32\\0navbench.jpg"
        var body = Data([0, deviceSequence])
        body.append(path.data(using: .utf16LittleEndian) ?? Data())
        body.append(contentsOf: [0, 0])
        try writeFrame(flag: 0, command: 0x20, body: body)
    }

    private func finish(_ frame: E87Frame) throws {
        let deviceSequence = frame.body.first ?? 0
        let status = frame.body.count > 1 ? frame.body[1] : 0xFF
        try writeFrame(flag: 0, command: 0x1C, body: Data([0, deviceSequence]))
        guard status == 0 else { throw E87Error.deviceRejected(status) }
    }

    private func writeFrame(flag: UInt8, command: UInt8, body: Data) throws {
        try write(E87Codec.frame(flag: flag, command: command, body: body), to: dataWriter)
    }

    private func write(_ data: Data, to characteristic: CBCharacteristic?) throws {
        guard let peripheral, let characteristic else { throw E87Error.notConnected }
        guard data.count <= peripheral.maximumWriteValueLength(for: .withoutResponse) else {
            throw E87Error.deviceRejected(0xFD)
        }
        peripheral.writeValue(data, for: characteristic, type: characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
    }

    private func waitFrame(command: UInt8, timeout: Double) async throws -> E87Frame {
        try await waitFrame(commands: [command], timeout: timeout)
    }

    private func waitFrame(commands: Set<UInt8>, timeout: Double) async throws -> E87Frame {
        let raw = try await waitRaw({ data in
            guard let frame = E87Codec.parse(data) else { return false }
            return commands.contains(frame.command)
        }, timeout: timeout, label: "command \(commands.map { String(format: "0x%02x", $0) }.joined(separator: ", "))")
        guard let frame = E87Codec.parse(raw) else { throw E87Error.deviceRejected(0xFC) }
        return frame
    }

    private func waitRaw(_ predicate: (Data) -> Bool, timeout: Double, label: String) async throws -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if let index = notifications.firstIndex(where: predicate) {
                return notifications.remove(at: index)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw E87Error.timeout(label)
    }

    private func appendLog(_ text: String) {
        logLines.append(text)
        if logLines.count > 100 {
            logLines.removeFirst(logLines.count - 100)
        }
    }

    private func resetConnection() {
        peripheral = nil; dataWriter = nil; controlWriter = nil
        notifications.removeAll(); authenticated = false; initialized = false
        isConnected = false; state = "Disconnected"
    }
}

extension E87BluetoothClient: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state == .poweredOn ? "Ready to scan" : "Bluetooth unavailable"
    }

    func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi _: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard ["E87", "L8", "X9", "LED Badge"].contains(where: { name.localizedCaseInsensitiveContains($0) }) else { return }
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
    }

    func centralManager(_: CBCentralManager, didConnect _: CBPeripheral) {
        connectedContinuation?.resume(); connectedContinuation = nil
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        connectedContinuation?.resume(throwing: error ?? E87Error.notConnected); connectedContinuation = nil
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error _: Error?) {
        resetConnection()
    }
}

extension E87BluetoothClient: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            discoveryContinuation?.resume(throwing: error); discoveryContinuation = nil; return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            discoveryContinuation?.resume(throwing: error); discoveryContinuation = nil; return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == ae01 {
                dataWriter = characteristic
            } else if characteristic.uuid == fd02 {
                controlWriter = characteristic
            } else if characteristic.uuid == ae02 || notifyUUIDs.contains(characteristic.uuid) {
                pendingNotificationUUIDs.insert(characteristic.uuid)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        finishDiscoveryIfReady(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            discoveryContinuation?.resume(throwing: error); discoveryContinuation = nil; return
        }
        if characteristic.isNotifying {
            pendingNotificationUUIDs.remove(characteristic.uuid)
        }
        finishDiscoveryIfReady(peripheral)
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        notifications.append(value)
        if notifications.count > 300 {
            notifications.removeFirst()
        }
    }

    private func finishDiscoveryIfReady(_ peripheral: CBPeripheral) {
        let servicesComplete = peripheral.services?.allSatisfy { $0.characteristics != nil } == true
        guard servicesComplete, dataWriter != nil, controlWriter != nil,
              pendingNotificationUUIDs.isEmpty, discoveryContinuation != nil else { return }
        discoveryContinuation?.resume()
        discoveryContinuation = nil
    }
}
