import Foundation

enum NavigationRenderer {
    struct RenderedFrame: Sendable {
        let jpeg: Data
        let encodeMilliseconds: Double
    }

    @MainActor
    static func render(direction: NavigationDirection, distance: String = "500 ft") throws -> RenderedFrame {
        let started = ContinuousClock.now
        let badgeDirection: BadgeFaceDirection = direction == .left ? .left : .right
        let export = try BadgeFaceRenderer.export(
            treatment: .clean,
            encoder: .badgeCompatible,
            quality: 0.10,
            direction: badgeDirection,
            instruction: "EXIT 24B",
            distance: distance.uppercased()
        )
        let elapsed = ContinuousClock.now - started
        return RenderedFrame(jpeg: export.jpeg, encodeMilliseconds: elapsed.milliseconds)
    }
}

extension Duration {
    var milliseconds: Double {
        let value = components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }
}
