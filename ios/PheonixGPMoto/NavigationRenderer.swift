import UIKit

enum NavigationRenderer {
    struct RenderedFrame: Sendable {
        let jpeg: Data
        let encodeMilliseconds: Double
    }

    @MainActor
    static func render(direction: NavigationDirection, distance: String = "500 ft") throws -> RenderedFrame {
        let started = ContinuousClock.now
        let size = CGSize(width: 368, height: 368)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let cg = context.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setFillColor(UIColor.white.cgColor)
            cg.setLineWidth(30)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let mirrored: CGFloat = direction == .left ? -1 : 1
            cg.saveGState()
            cg.translateBy(x: 184, y: 0)
            cg.scaleBy(x: mirrored, y: 1)
            cg.translateBy(x: -184, y: 0)
            cg.move(to: CGPoint(x: 105, y: 185))
            cg.addLine(to: CGPoint(x: 250, y: 185))
            cg.addLine(to: CGPoint(x: 250, y: 270))
            cg.strokePath()
            cg.move(to: CGPoint(x: 105, y: 185))
            cg.addLine(to: CGPoint(x: 165, y: 125))
            cg.addLine(to: CGPoint(x: 165, y: 245))
            cg.closePath()
            cg.fillPath()
            cg.restoreGState()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 42, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
            ]
            distance.draw(in: CGRect(x: 44, y: 52, width: 280, height: 55), withAttributes: attributes)
        }
        guard let data = image.jpegData(compressionQuality: 0.42) else {
            throw E87Error.jpegEncodingFailed
        }
        let elapsed = ContinuousClock.now - started
        return RenderedFrame(jpeg: data, encodeMilliseconds: elapsed.milliseconds)
    }
}

extension Duration {
    var milliseconds: Double {
        let value = components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }
}
