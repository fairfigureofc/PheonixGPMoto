import CoreBluetooth
import Foundation
import Observation

@MainActor
@Observable
final class BenchmarkModel {
    let bluetooth = E87BluetoothClient()
    var metrics: [BenchmarkMetric] = []
    var cadenceSeconds = 1.0
    var requestedCycles = 20
    var isRunning = false
    var status = "Connect a badge to begin."
    private var benchmarkTask: Task<Void, Never>?

    func connect(_ peripheral: CBPeripheral) {
        Task {
            do {
                try await bluetooth.connect(peripheral)
                status = "Connected. Ready to benchmark."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func start() {
        guard bluetooth.isConnected, !isRunning else { return }
        metrics.removeAll()
        isRunning = true
        status = "Benchmark running…"
        benchmarkTask = Task {
            for cycle in 1...requestedCycles {
                guard !Task.isCancelled else { break }
                let cycleStarted = ContinuousClock.now
                let direction: NavigationDirection = cycle.isMultiple(of: 2) ? .right : .left
                do {
                    let rendered = try NavigationRenderer.render(direction: direction)
                    let upload = try await bluetooth.upload(jpeg: rendered.jpeg)
                    let total = (ContinuousClock.now - cycleStarted).milliseconds
                    metrics.append(BenchmarkMetric(cycle: cycle, direction: direction, jpegBytes: rendered.jpeg.count, encodeMilliseconds: rendered.encodeMilliseconds, uploadMilliseconds: upload, cycleMilliseconds: total, succeeded: true, error: nil))
                    let remaining = cadenceSeconds - total / 1_000
                    if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                } catch {
                    let total = (ContinuousClock.now - cycleStarted).milliseconds
                    metrics.append(BenchmarkMetric(cycle: cycle, direction: direction, jpegBytes: 0, encodeMilliseconds: 0, uploadMilliseconds: 0, cycleMilliseconds: total, succeeded: false, error: error.localizedDescription))
                    status = "Cycle \(cycle) failed: \(error.localizedDescription)"
                    break
                }
            }
            isRunning = false
            if metrics.allSatisfy(\.succeeded) { status = summary }
        }
    }

    func stop() {
        benchmarkTask?.cancel()
        benchmarkTask = nil
        isRunning = false
        status = "Stopped."
    }

    var summary: String {
        let successful = metrics.filter(\.succeeded)
        guard !successful.isEmpty else { return "No successful cycles yet." }
        let sorted = successful.map(\.uploadMilliseconds).sorted()
        let p95Index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        let average = sorted.reduce(0, +) / Double(sorted.count)
        return String(format: "%d/%d succeeded · avg %.0f ms · p95 %.0f ms", successful.count, metrics.count, average, sorted[p95Index])
    }
}
