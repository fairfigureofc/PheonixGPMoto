import CoreGraphics
import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Minimal baseline JPEG encoder for the Jieli decoder in the E87 badge.
///
/// Image I/O optimizes Huffman tables for each image. The badge accepts the
/// transfer but cannot decode those tables, producing a black screen. This
/// encoder deliberately emits the fixed ISO/JFIF luminance tables used by
/// jpeg-js and libjpeg's non-optimized baseline mode.
enum BadgeCompatibleJPEGEncoder {
    private struct HuffmanCode {
        let bits: UInt16
        let length: Int
    }

    private struct BitWriter {
        private(set) var data = Data()
        private var byte: UInt8 = 0
        private var bitCount = 0

        mutating func write(_ bits: UInt16, length: Int) {
            guard length > 0 else { return }
            for shift in stride(from: length - 1, through: 0, by: -1) {
                byte = (byte << 1) | UInt8((bits >> shift) & 1)
                bitCount += 1
                if bitCount == 8 {
                    append(byte)
                    byte = 0
                    bitCount = 0
                }
            }
        }

        mutating func finish() {
            guard bitCount > 0 else { return }
            let padding = 8 - bitCount
            byte = (byte << padding) | UInt8((1 << padding) - 1)
            append(byte)
            byte = 0
            bitCount = 0
        }

        private mutating func append(_ value: UInt8) {
            data.append(value)
            if value == 0xFF {
                data.append(0x00)
            }
        }
    }

    private static let zigzag = [
        0, 1, 8, 16, 9, 2, 3, 10,
        17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34,
        27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36,
        29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46,
        53, 60, 61, 54, 47, 55, 62, 63,
    ]

    private static let baseQuantization = [
        16, 11, 10, 16, 24, 40, 51, 61,
        12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56,
        14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77,
        24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101,
        72, 92, 95, 98, 112, 100, 103, 99,
    ]

    private static let dcCounts = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
    private static let dcValues = Array(0 ... 11)
    private static let acCounts = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125]
    private static let acValues = [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
        0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
        0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
        0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16,
        0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
        0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
        0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
        0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
        0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
        0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
        0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4,
        0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
        0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
        0xF9, 0xFA,
    ]

    private static let cosine: [[Double]] = (0 ..< 8).map { frequency in
        (0 ..< 8).map { position in
            cos(Double((2 * position + 1) * frequency) * .pi / 16)
        }
    }

    #if canImport(UIKit)
        @MainActor
        static func encode(_ image: UIImage, quality: Int) -> Data? {
            guard let cgImage = image.cgImage else { return nil }
            let width = cgImage.width
            let height = cgImage.height
            var pixels = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }

            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return encode(pixels: pixels, width: width, height: height, quality: quality)
        }
    #endif

    static func encode(pixels: [UInt8], width: Int, height: Int, quality: Int) -> Data? {
        guard width > 0, height > 0, width <= 65535, height <= 65535,
              pixels.count == width * height
        else { return nil }

        let quantization = quantizationTable(quality: quality)
        let dcTable = huffmanTable(counts: dcCounts, values: dcValues)
        let acTable = huffmanTable(counts: acCounts, values: acValues)
        var output = Data([0xFF, 0xD8])

        appendSegment(0xE0, payload: [
            0x4A, 0x46, 0x49, 0x46, 0x00,
            0x01, 0x01, 0x00,
            0x00, 0x01, 0x00, 0x01,
            0x00, 0x00,
        ], to: &output)
        appendSegment(0xDB, payload: [0x00] + zigzag.map { UInt8(quantization[$0]) }, to: &output)
        appendSegment(0xC0, payload: [
            0x08,
            UInt8((height >> 8) & 0xFF), UInt8(height & 0xFF),
            UInt8((width >> 8) & 0xFF), UInt8(width & 0xFF),
            0x01,
            0x01, 0x11, 0x00,
        ], to: &output)

        let huffmanPayload = [UInt8(0x00)]
            + dcCounts.map(UInt8.init)
            + dcValues.map(UInt8.init)
            + [UInt8(0x10)]
            + acCounts.map(UInt8.init)
            + acValues.map(UInt8.init)
        appendSegment(0xC4, payload: huffmanPayload, to: &output)
        appendSegment(0xDA, payload: [
            0x01,
            0x01, 0x00,
            0x00, 0x3F, 0x00,
        ], to: &output)

        var writer = BitWriter()
        var previousDC = 0
        for blockY in stride(from: 0, to: height, by: 8) {
            for blockX in stride(from: 0, to: width, by: 8) {
                let coefficients = quantizedBlock(
                    pixels: pixels,
                    width: width,
                    height: height,
                    x: blockX,
                    y: blockY,
                    quantization: quantization
                )
                write(
                    coefficients: coefficients,
                    previousDC: &previousDC,
                    dcTable: dcTable,
                    acTable: acTable,
                    writer: &writer
                )
            }
        }
        writer.finish()
        output.append(writer.data)
        output.append(contentsOf: [0xFF, 0xD9])
        return output
    }

    private static func quantizationTable(quality: Int) -> [Int] {
        let clamped = min(100, max(1, quality))
        let scale = clamped < 50 ? 5000 / clamped : 200 - clamped * 2
        return baseQuantization.map { min(255, max(1, ($0 * scale + 50) / 100)) }
    }

    private static func huffmanTable(counts: [Int], values: [Int]) -> [HuffmanCode] {
        var table = [HuffmanCode](repeating: .init(bits: 0, length: 0), count: 256)
        var code: UInt16 = 0
        var index = 0
        for length in 1 ... 16 {
            for _ in 0 ..< counts[length - 1] {
                table[values[index]] = .init(bits: code, length: length)
                code += 1
                index += 1
            }
            code <<= 1
        }
        return table
    }

    private static func quantizedBlock(
        pixels: [UInt8],
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        quantization: [Int]
    ) -> [Int] {
        var intermediate = [Double](repeating: 0, count: 64)
        for row in 0 ..< 8 {
            let sourceY = min(height - 1, y + row)
            for frequencyX in 0 ..< 8 {
                var sum = 0.0
                for column in 0 ..< 8 {
                    let sourceX = min(width - 1, x + column)
                    let sample = Double(pixels[sourceY * width + sourceX]) - 128
                    sum += sample * cosine[frequencyX][column]
                }
                intermediate[row * 8 + frequencyX] = sum
            }
        }

        var result = [Int](repeating: 0, count: 64)
        for frequencyY in 0 ..< 8 {
            let verticalScale = frequencyY == 0 ? 1 / sqrt(2.0) : 1
            for frequencyX in 0 ..< 8 {
                let horizontalScale = frequencyX == 0 ? 1 / sqrt(2.0) : 1
                var sum = 0.0
                for row in 0 ..< 8 {
                    sum += intermediate[row * 8 + frequencyX] * cosine[frequencyY][row]
                }
                let naturalIndex = frequencyY * 8 + frequencyX
                let coefficient = 0.25 * horizontalScale * verticalScale * sum
                result[naturalIndex] = Int((coefficient / Double(quantization[naturalIndex])).rounded())
            }
        }
        return result
    }

    private static func write(
        coefficients: [Int],
        previousDC: inout Int,
        dcTable: [HuffmanCode],
        acTable: [HuffmanCode],
        writer: inout BitWriter
    ) {
        let difference = coefficients[0] - previousDC
        previousDC = coefficients[0]
        let dcSize = magnitudeBitCount(difference)
        let dcCode = dcTable[dcSize]
        writer.write(dcCode.bits, length: dcCode.length)
        writer.write(amplitudeBits(difference, size: dcSize), length: dcSize)

        var zeroRun = 0
        for zigzagIndex in 1 ..< 64 {
            let value = coefficients[zigzag[zigzagIndex]]
            if value == 0 {
                zeroRun += 1
                continue
            }
            while zeroRun >= 16 {
                let zrl = acTable[0xF0]
                writer.write(zrl.bits, length: zrl.length)
                zeroRun -= 16
            }
            let size = magnitudeBitCount(value)
            let symbol = zeroRun * 16 + size
            let code = acTable[symbol]
            writer.write(code.bits, length: code.length)
            writer.write(amplitudeBits(value, size: size), length: size)
            zeroRun = 0
        }
        if zeroRun > 0 {
            let eob = acTable[0x00]
            writer.write(eob.bits, length: eob.length)
        }
    }

    private static func magnitudeBitCount(_ value: Int) -> Int {
        guard value != 0 else { return 0 }
        return Int.bitWidth - abs(value).leadingZeroBitCount
    }

    private static func amplitudeBits(_ value: Int, size: Int) -> UInt16 {
        guard size > 0 else { return 0 }
        if value >= 0 {
            return UInt16(value)
        }
        return UInt16(value + (1 << size) - 1)
    }

    private static func appendSegment(_ marker: UInt8, payload: [UInt8], to output: inout Data) {
        let length = payload.count + 2
        output.append(contentsOf: [
            0xFF, marker,
            UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
        ])
        output.append(contentsOf: payload)
    }
}
