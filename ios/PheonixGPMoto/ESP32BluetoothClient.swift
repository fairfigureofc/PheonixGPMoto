import Combine
@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class ESP32BluetoothClient: NSObject, ObservableObject {
    @Published private(set) var state = "Bluetooth starting…"
    @Published private(set) var discovered: [CBPeripheral] = []
    @Published private(set) var isConnected = false
    @Published private(set) var lastSend = "Nothing sent yet"

    private let serviceUUID = CBUUID(string: "6F4A0001-6F74-4F4D-8A48-50484F454E58")
    private let navigationUUID = CBUUID(string: "6F4A0002-6F74-4F4D-8A48-50484F454E58")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var navigationCharacteristic: CBCharacteristic?
    private var shouldAutoConnect = false
    private var isWriteInFlight = false
    private var pendingPacket: NavigationPacket?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else {
            state = "Turn Bluetooth on"
            return
        }
        discovered.removeAll()
        state = "Scanning for Pheonix Moto…"
        central.scanForPeripherals(withServices: [serviceUUID])
    }

    func startAutoConnect() {
        shouldAutoConnect = true
        if isConnected {
            return
        }
        scan()
    }

    func stop() {
        shouldAutoConnect = false
        central.stopScan()
        pendingPacket = nil
    }

    func connect(_ target: CBPeripheral) {
        central.stopScan()
        peripheral = target
        target.delegate = self
        state = "Connecting…"
        central.connect(target)
    }

    func send(_ packet: NavigationPacket) {
        guard let peripheral, let characteristic = navigationCharacteristic else {
            return
        }
        guard !isWriteInFlight else {
            pendingPacket = packet
            return
        }
        let payload = packet.encoded()
        isWriteInFlight = true
        peripheral.writeValue(payload, for: characteristic, type: .withResponse)
        lastSend = "Sent sequence \(packet.sequence): \(packet.roadName), \(packet.distanceToTurnMeters) m"
    }
}

extension ESP32BluetoothClient: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state == .poweredOn ? "Ready to scan" : "Bluetooth unavailable"
        if central.state == .poweredOn, shouldAutoConnect {
            scan()
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        guard !discovered.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        discovered.append(peripheral)
        if shouldAutoConnect, self.peripheral == nil {
            connect(peripheral)
        }
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = "Discovering navigation service…"
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        peripheral = nil
        state = error?.localizedDescription ?? "Connection failed"
        reconnectIfNeeded()
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error _: Error?) {
        peripheral = nil
        navigationCharacteristic = nil
        isConnected = false
        isWriteInFlight = false
        state = "Disconnected"
        reconnectIfNeeded()
    }

    private func reconnectIfNeeded() {
        guard shouldAutoConnect, central.state == .poweredOn else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, shouldAutoConnect, !self.isConnected else { return }
            scan()
        }
    }
}

extension ESP32BluetoothClient: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            state = error?.localizedDescription ?? "Service discovery failed"
            return
        }
        for service in peripheral.services ?? [] where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([navigationUUID], for: service)
        }
    }

    func peripheral(_: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            state = error?.localizedDescription ?? "Characteristic discovery failed"
            return
        }
        navigationCharacteristic = service.characteristics?.first(where: { $0.uuid == navigationUUID })
        isConnected = navigationCharacteristic != nil
        state = isConnected ? "Connected to Pheonix Moto" : "Navigation characteristic missing"
    }

    func peripheral(_: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: Error?) {
        isWriteInFlight = false
        if let error {
            state = "Display update failed: \(error.localizedDescription)"
        }
        guard let pendingPacket else { return }
        self.pendingPacket = nil
        send(pendingPacket)
    }
}
