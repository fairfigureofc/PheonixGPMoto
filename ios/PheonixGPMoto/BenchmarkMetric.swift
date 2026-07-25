import Foundation

struct BenchmarkMetric: Identifiable, Sendable {
    let id = UUID()
    let cycle: Int
    let direction: NavigationDirection
    let jpegBytes: Int
    let encodeMilliseconds: Double
    let uploadMilliseconds: Double
    let cycleMilliseconds: Double
    let succeeded: Bool
    let error: String?
}

enum NavigationDirection: String, Sendable {
    case left
    case right
}
