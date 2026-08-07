import SwiftUI

struct ContentView: View {
    @Bindable var model: BenchmarkModel
    @ObservedObject private var bluetooth: E87BluetoothClient

    init(model: BenchmarkModel) {
        self.model = model
        bluetooth = model.bluetooth
    }

    var body: some View {
        TabView {
            MapsHomeView()
                .tabItem {
                    Label("Ride", systemImage: "map")
                }

            ESP32DemoView()
                .tabItem {
                    Label("ESP32 Demo", systemImage: "display")
                }

            benchmarkView
                .tabItem {
                    Label("BLE Bench", systemImage: "antenna.radiowaves.left.and.right")
                }

            BadgeFaceLabView()
                .tabItem {
                    Label("Face Lab", systemImage: "circle.grid.cross")
                }
        }
    }

    private var benchmarkView: some View {
        NavigationStack {
            List {
                Section("Badge") {
                    HStack {
                        Circle().fill(bluetooth.isConnected ? .green : .secondary).frame(width: 10, height: 10)
                        Text(bluetooth.state)
                        Spacer()
                        Button("Scan") { model.bluetooth.scan() }.disabled(model.isRunning)
                    }
                    ForEach(bluetooth.discovered, id: \.identifier) { peripheral in
                        Button {
                            model.connect(peripheral)
                        } label: {
                            HStack {
                                Text(peripheral.name ?? "E87 Badge")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }

                Section("Benchmark") {
                    LabeledContent("Target cadence") {
                        Picker("Target cadence", selection: $model.cadenceSeconds) {
                            Text("0.25 s").tag(0.25)
                            Text("0.5 s").tag(0.5)
                            Text("1.0 s").tag(1.0)
                            Text("2.0 s").tag(2.0)
                        }.pickerStyle(.menu)
                    }
                    Stepper("Cycles: \(model.requestedCycles)", value: $model.requestedCycles, in: 2 ... 100, step: 2)
                    HStack {
                        Button(model.isRunning ? "Running…" : "Start") { model.start() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!bluetooth.isConnected || model.isRunning)
                        if model.isRunning {
                            Button("Stop", role: .destructive) { model.stop() }
                        }
                    }
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                }

                if let jpeg = model.latestJPEG, let image = UIImage(data: jpeg) {
                    Section("Exact JPEG sent to badge") {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .clipShape(Circle())
                        LabeledContent("Size", value: "\(jpeg.count) bytes")
                    }
                }

                if !model.metrics.isEmpty {
                    Section("Results") {
                        Text(model.summary).font(.headline)
                        ForEach(model.metrics) { metric in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: metric.direction == .left ? "arrow.turn.up.left" : "arrow.turn.up.right")
                                    Text("Cycle \(metric.cycle)")
                                    Spacer()
                                    Image(systemName: metric.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(metric.succeeded ? .green : .red)
                                }
                                if metric.succeeded {
                                    Text(String(format: "%d B · encode %.0f ms · BLE %.0f ms · total %.0f ms", metric.jpegBytes, metric.encodeMilliseconds, metric.uploadMilliseconds, metric.cycleMilliseconds))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                } else {
                                    Text(metric.error ?? "Unknown error").font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                Section("Interpretation") {
                    Text("A cadence passes when every cycle succeeds and BLE p95 stays below the target interval. Visually confirm screen-change latency because the badge does not send a display-presented event.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if !bluetooth.logLines.isEmpty {
                    Section("Device Log") {
                        ForEach(Array(bluetooth.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("PheonixGPMoto")
        }
    }
}
