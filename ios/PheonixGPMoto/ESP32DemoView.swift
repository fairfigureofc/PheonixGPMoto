import SwiftUI

struct ESP32DemoView: View {
    @StateObject private var bluetooth = ESP32BluetoothClient()
    @State private var sequence: UInt16 = 1
    @State private var maneuver = NavigationPacket.Maneuver.left
    @State private var lightMode = false
    @State private var roadName = "VAN NESS AVE"
    @State private var distanceMeters = 152
    @State private var remainingMiles = 86.4
    @State private var remainingMinutes = 102

    var body: some View {
        NavigationStack {
            Form {
                Section("ESP32") {
                    LabeledContent("Status", value: bluetooth.state)
                    Button("Scan for display") { bluetooth.scan() }
                    ForEach(bluetooth.discovered, id: \.identifier) { peripheral in
                        Button("Connect to \(peripheral.name ?? "Pheonix Moto")") {
                            bluetooth.connect(peripheral)
                        }
                    }
                }

                Section("Sample maneuver") {
                    TextField("Road name", text: $roadName)
                    Picker("Maneuver", selection: $maneuver) {
                        ForEach(NavigationPacket.Maneuver.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Toggle("Light mode", isOn: $lightMode)
                    Stepper("Turn in \(distanceMeters) m", value: $distanceMeters, in: 10 ... 2000, step: 10)
                    Stepper(
                        String(format: "%.1f miles remaining", remainingMiles),
                        value: $remainingMiles,
                        in: 0 ... 1000,
                        step: 0.5
                    )
                    Stepper("\(remainingMinutes) minutes remaining", value: $remainingMinutes, in: 0 ... 1440)
                }

                Section {
                    Button("Send sample navigation", action: sendSample)
                        .buttonStyle(.borderedProminent)
                        .disabled(!bluetooth.isConnected)
                    Text(bluetooth.lastSend)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ESP32 Hello World")
        }
    }

    private func sendSample() {
        bluetooth.send(NavigationPacket(
            sequence: sequence,
            maneuver: maneuver,
            lightMode: lightMode,
            distanceToTurnMeters: UInt32(distanceMeters),
            remainingMeters: UInt32(remainingMiles * 1609.344),
            remainingSeconds: UInt32(remainingMinutes * 60),
            roadName: roadName
        ))
        sequence &+= 1
    }
}
