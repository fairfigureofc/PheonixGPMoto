import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum BadgeFaceTreatment: String, CaseIterable, Identifiable {
    case clean = "Clean"
    case divider = "Divider"
    case shield = "Exit shield"

    var id: Self {
        self
    }
}

enum BadgeFaceDirection: String, CaseIterable, Identifiable {
    case left = "Left"
    case straight = "Straight"
    case right = "Right"

    var id: Self {
        self
    }
}

enum BadgeJPEGEncoder: String, CaseIterable, Identifiable {
    case uiKit = "UIKit"
    case imageIO = "Image I/O"
    case imageIOGrayscale = "Grayscale"

    var id: Self {
        self
    }
}

struct BadgeFaceExport: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpeg: Data
    let treatment: BadgeFaceTreatment
    let encoder: BadgeJPEGEncoder
    let quality: Double

    var filename: String {
        let treatmentName = treatment.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        return "pheonix-\(treatmentName)-\(encoder.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-q\(Int(quality * 100)).jpg"
    }
}

@MainActor
enum BadgeFaceRenderer {
    static let size = CGSize(width: 368, height: 368)

    static func export(
        treatment: BadgeFaceTreatment,
        encoder: BadgeJPEGEncoder,
        quality: Double,
        direction: BadgeFaceDirection = .left,
        instruction: String = "EXIT 24B",
        distance: String = "500 FT"
    ) throws -> BadgeFaceExport {
        let image = render(
            treatment: treatment,
            direction: direction,
            instruction: instruction,
            distance: distance
        )
        let jpeg: Data? = switch encoder {
        case .uiKit:
            image.jpegData(compressionQuality: quality)
        case .imageIO:
            encodeWithImageIO(image, quality: quality)
        case .imageIOGrayscale:
            grayscaleCGImage(from: image).flatMap {
                encodeWithImageIO($0, quality: quality)
            }
        }
        guard let jpeg else { throw E87Error.jpegEncodingFailed }
        return BadgeFaceExport(
            image: image,
            jpeg: jpeg,
            treatment: treatment,
            encoder: encoder,
            quality: quality
        )
    }

    static func bestExport(
        treatment: BadgeFaceTreatment,
        encoder: BadgeJPEGEncoder,
        direction: BadgeFaceDirection,
        maximumBytes: Int
    ) -> BadgeFaceExport? {
        var lowerBound = 0.01
        var upperBound = 0.8
        var best: BadgeFaceExport?
        for _ in 0 ..< 9 {
            let candidate = (lowerBound + upperBound) / 2
            guard let export = try? export(
                treatment: treatment,
                encoder: encoder,
                quality: candidate,
                direction: direction
            ) else { return best }
            if export.jpeg.count <= maximumBytes {
                best = export
                lowerBound = candidate
            } else {
                upperBound = candidate
            }
        }
        return best
    }

    private static func render(
        treatment: BadgeFaceTreatment,
        direction: BadgeFaceDirection,
        instruction: String,
        distance: String
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            drawCentered(instruction, y: 46, size: 34)
            if treatment == .shield {
                let shield = UIBezierPath(roundedRect: CGRect(x: 119, y: 28, width: 130, height: 62), cornerRadius: 18)
                UIColor.white.setStroke()
                shield.lineWidth = 5
                shield.stroke()
            }

            drawCentered(distance, y: 108, size: 28)
            if treatment == .divider {
                let divider = UIBezierPath()
                divider.move(to: CGPoint(x: 86, y: 158))
                divider.addLine(to: CGPoint(x: 282, y: 158))
                UIColor(white: 0.55, alpha: 1).setStroke()
                divider.lineWidth = 3
                divider.stroke()
            }

            drawArrow(direction, in: context.cgContext)
        }
    }

    private static func drawCentered(_ text: String, y: CGFloat, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.draw(
            in: CGRect(x: 28, y: y, width: 312, height: size + 16),
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: size, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private static func drawArrow(_ direction: BadgeFaceDirection, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(22)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch direction {
        case .left:
            context.move(to: CGPoint(x: 258, y: 245))
            context.addLine(to: CGPoint(x: 112, y: 245))
            context.move(to: CGPoint(x: 112, y: 245))
            context.addLine(to: CGPoint(x: 158, y: 199))
            context.move(to: CGPoint(x: 112, y: 245))
            context.addLine(to: CGPoint(x: 158, y: 291))
        case .straight:
            context.move(to: CGPoint(x: 184, y: 310))
            context.addLine(to: CGPoint(x: 184, y: 184))
            context.move(to: CGPoint(x: 184, y: 184))
            context.addLine(to: CGPoint(x: 140, y: 228))
            context.move(to: CGPoint(x: 184, y: 184))
            context.addLine(to: CGPoint(x: 228, y: 228))
        case .right:
            context.move(to: CGPoint(x: 110, y: 245))
            context.addLine(to: CGPoint(x: 256, y: 245))
            context.move(to: CGPoint(x: 256, y: 245))
            context.addLine(to: CGPoint(x: 210, y: 199))
            context.move(to: CGPoint(x: 256, y: 245))
            context.addLine(to: CGPoint(x: 210, y: 291))
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func encodeWithImageIO(_ image: UIImage, quality: Double) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        return encodeWithImageIO(cgImage, quality: quality)
    }

    private static func grayscaleCGImage(from image: UIImage) -> CGImage? {
        guard let source = image.cgImage else { return nil }
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    private static func encodeWithImageIO(_ cgImage: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyJFIFDictionary: [:],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

struct BadgeFaceLabView: View {
    @State private var treatment = BadgeFaceTreatment.clean
    @State private var direction = BadgeFaceDirection.left
    @State private var encoder = BadgeJPEGEncoder.imageIO
    @State private var quality = 0.42
    @State private var export: BadgeFaceExport?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Treatment") {
                    Picker("Treatment", selection: $treatment) {
                        ForEach(BadgeFaceTreatment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Direction", selection: $direction) {
                        ForEach(BadgeFaceDirection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Compression") {
                    Picker("Encoder", selection: $encoder) {
                        ForEach(BadgeJPEGEncoder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Slider(value: $quality, in: 0.1 ... 0.8, step: 0.02) {
                        Text("Quality")
                    }
                    LabeledContent("Quality", value: "\(Int(quality * 100))%")
                }

                Section("Byte-budget search") {
                    budgetResult(maximumBytes: 3500, label: "Comfort target")
                    budgetResult(maximumBytes: 3920, label: "One-window limit")
                }

                if let export {
                    Section("368 × 368 preview") {
                        Image(uiImage: UIImage(data: export.jpeg) ?? export.image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.secondary, lineWidth: 1))
                            .padding(.horizontal, 18)

                        LabeledContent("JPEG size", value: ByteCountFormatter.string(fromByteCount: Int64(export.jpeg.count), countStyle: .file))
                        LabeledContent("Transfer chunks", value: "\((export.jpeg.count + 489) / 490)")
                        LabeledContent("One E87 window", value: export.jpeg.count <= 3920 ? "Yes" : "No")

                        Button("Export JPEG", systemImage: "square.and.arrow.up") {
                            shareURL = writeTemporary(export)
                        }
                    }
                }

                Section("Quick comparison") {
                    ForEach([0.2, 0.3, 0.42, 0.55], id: \.self) { candidate in
                        if let sample = try? BadgeFaceRenderer.export(
                            treatment: treatment,
                            encoder: encoder,
                            quality: candidate,
                            direction: direction
                        ) {
                            LabeledContent("Quality \(Int(candidate * 100))%") {
                                Text("\(sample.jpeg.count) B · \((sample.jpeg.count + 489) / 490) chunks")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Badge Face Lab")
            .onAppear(perform: refresh)
            .onChange(of: treatment) { refresh() }
            .onChange(of: direction) { refresh() }
            .onChange(of: encoder) { refresh() }
            .onChange(of: quality) { refresh() }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: {
                    if !$0 {
                        shareURL = nil
                    }
                }
            )) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
        }
    }

    private func refresh() {
        export = try? BadgeFaceRenderer.export(
            treatment: treatment,
            encoder: encoder,
            quality: quality,
            direction: direction
        )
    }

    @ViewBuilder
    private func budgetResult(maximumBytes: Int, label: String) -> some View {
        if let result = BadgeFaceRenderer.bestExport(
            treatment: treatment,
            encoder: encoder,
            direction: direction,
            maximumBytes: maximumBytes
        ) {
            LabeledContent(label) {
                Text("q\(Int(result.quality * 100)) · \(result.jpeg.count) B")
                    .monospacedDigit()
            }
        } else {
            LabeledContent(label, value: "Cannot fit")
                .foregroundStyle(.orange)
        }
    }

    private func writeTemporary(_ export: BadgeFaceExport) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.filename)
        do {
            try export.jpeg.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
