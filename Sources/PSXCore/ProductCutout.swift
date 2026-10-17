import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Vision

/// GPT 빠른 배경 제거:
/// 1. macOS Vision이 사진 속 물체들을 찾아 번호를 매기고 (1초 안팎)
/// 2. 번호를 표시한 작은 사진을 GPT에게 보여 "어느 번호가 상품인지"만 묻고 (글 한 줄 답변이라 빠름)
/// 3. 고른 물체만 Vision 마스크로 오려 냅니다. 사진을 새로 그리지 않아 상품은 원본 그대로입니다.
public enum ProductCutout {
    /// 흰색(기본) 또는 투명 배경으로 상품만 남깁니다.
    public static func run(_ image: CGImage, picker: any AIProductPicker, transparent: Bool) async throws -> CGImage {
        let segmentation = try ForegroundSegmentation(image)
        let keep = try await choose(labels: segmentation.labels, areas: segmentation.areas,
                                    overlay: { try segmentation.overlay() }, picker: picker)
        let cutout = try segmentation.cutout(keep)
        return try transparent ? cutout : ImageOps.flatten(cutout)
    }

    /// 남길 물체 번호를 정합니다. 물체가 하나면 묻지 않고, GPT가 고르지 못하면 가장 큰 물체를 남깁니다.
    static func choose(labels: [Int], areas: [Int: Int], overlay: () throws -> CGImage,
                       picker: any AIProductPicker) async throws -> [Int] {
        guard labels.count > 1 else { return labels }
        let picked = try await picker.pickProduct(in: overlay(), labels: labels)
        let valid = picked.filter(labels.contains)
        if !valid.isEmpty { return Array(Set(valid)).sorted() }
        return labels.max { areas[$0, default: 0] < areas[$1, default: 0] }.map { [$0] } ?? labels
    }
}

/// 번호가 표시된 사진을 보고 상품에 해당하는 번호를 고르는 AI
public protocol AIProductPicker: Sendable {
    func pickProduct(in overlay: CGImage, labels: [Int]) async throws -> [Int]
}

public enum ProductPickPrompt {
    static func text(labels: [Int]) -> String {
        """
        This is a product photo for an online store. The detected objects are tinted in color and \
        marked with numbered badges (\(labels.map(String.init).joined(separator: ", "))). The darkened area is background.
        Which numbers belong to the main product being sold? Include every part of the product \
        (and all units if several identical products are shown). Exclude icons, badges, logos, captions, \
        overlaid text, prices, watermarks, stickers, props and decorations that are not part of the product.
        Reply with JSON only, for example {"keep":[1,3]}
        """
    }

    /// 답변에서 번호를 꺼냅니다. {"keep":[...]}가 있으면 그것을, 없으면 글에 나온 숫자를 씁니다.
    public static func parseLabels(_ text: String, valid: [Int]) -> [Int] {
        let candidates: [Int]
        if let range = text.range(of: #"\{[^{}]*\}"#, options: .regularExpression),
           let data = String(text[range]).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let keep = object["keep"] as? [Any] {
            candidates = keep.compactMap { ($0 as? NSNumber)?.intValue ?? Int("\($0)") }
        } else {
            candidates = text.matches(of: #/\d+/#).compactMap { Int($0.output) }
        }
        var seen = Set<Int>()
        return candidates.filter { valid.contains($0) && seen.insert($0).inserted }
    }
}

// MARK: - Vision 물체 분리

/// Vision으로 사진 속 물체(인스턴스)를 한 번 찾아 두고, 번호 표시 사진과 오려 내기에 다시 씁니다.
public final class ForegroundSegmentation: @unchecked Sendable {
    /// 물체 번호 (1부터)
    public let labels: [Int]
    /// 번호별 넓이(마스크 픽셀 수)
    public let areas: [Int: Int]

    private let image: CGImage
    private let observation: VNInstanceMaskObservation
    private let handler: VNImageRequestHandler
    private let mask: LabelMap

    public init(_ image: CGImage) throws {
        do {
            (observation, handler) = try Self.detect(image, cpuOnly: false)
        } catch ImageError.noForeground {
            throw ImageError.noForeground
        } catch {
            do {
                (observation, handler) = try Self.detect(image, cpuOnly: true)
            } catch ImageError.noForeground {
                throw ImageError.noForeground
            } catch {
                throw ImageError.backgroundRemovalFailed(error.localizedDescription)
            }
        }
        self.image = image
        mask = LabelMap(observation.instanceMask)
        labels = observation.allInstances.sorted()
        areas = mask.areas(of: labels)
    }

    /// 가장 넓은 물체 번호
    public var largest: Int? {
        labels.max { areas[$0, default: 0] < areas[$1, default: 0] }
    }

    /// GPT에게 보여 줄, 물체마다 색과 번호를 표시한 작은 사진
    public func overlay(maxPixelSize: Int = 768) throws -> CGImage {
        try ImageOps.makeOverlay(photo: image, mask: mask, labels: labels, maxPixelSize: maxPixelSize)
    }

    /// 고른 물체만 남기고 나머지는 투명하게 (원본 크기)
    public func cutout(_ instances: [Int]) throws -> CGImage {
        let buffer = try observation.generateMaskedImage(
            ofInstances: IndexSet(instances), from: handler, croppedToInstancesExtent: false)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            throw ImageError.renderFailed
        }
        return output
    }

    private static func detect(_ image: CGImage, cpuOnly: Bool) throws -> (VNInstanceMaskObservation, VNImageRequestHandler) {
        let request = VNGenerateForegroundInstanceMaskRequest()
        if cpuOnly {
            for (stage, devices) in try request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu(_) = $0 { return true } else { return false } }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ImageError.noForeground
        }
        return (observation, handler)
    }
}

/// 픽셀마다 물체 번호(0은 배경)가 든 마스크. 첫 줄이 위쪽.
struct LabelMap {
    let width: Int
    let height: Int
    let values: [UInt8]

    init(width: Int, height: Int, values: [UInt8]) {
        self.width = width
        self.height = height
        self.values = values
    }

    init(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        width = CVPixelBufferGetWidth(buffer)
        height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var values = [UInt8](repeating: 0, count: width * height)
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width { values[y * width + x] = row[x] }
            }
        }
        self.values = values
    }

    func areas(of labels: [Int]) -> [Int: Int] {
        var counts = [Int](repeating: 0, count: 256)
        for value in values { counts[Int(value)] += 1 }
        return Dictionary(uniqueKeysWithValues: labels.filter { $0 < 256 }.map { ($0, counts[$0]) })
    }
}

// MARK: - 번호 표시 사진

extension ImageOps {
    static let overlayColors: [(CGFloat, CGFloat, CGFloat)] = [
        (1.00, 0.23, 0.19), (0.20, 0.78, 0.35), (0.00, 0.48, 1.00), (1.00, 0.80, 0.00),
        (0.69, 0.32, 0.87), (1.00, 0.58, 0.00), (0.35, 0.78, 0.98), (1.00, 0.18, 0.57)
    ]

    /// 배경은 어둡게, 물체는 색을 입히고 가운데에 번호를 붙인 사진을 만듭니다.
    static func makeOverlay(photo: CGImage, mask: LabelMap, labels: [Int], maxPixelSize: Int) throws -> CGImage {
        let base = try downscaled(photo, maxPixelSize: maxPixelSize)
        let width = base.width, height = base.height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageError.renderFailed
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(base, in: rect)

        // 마스크 크기의 색 입힌 막 (premultiplied RGBA)
        let colorIndex = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        var tint = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        var sums: [Int: (x: Int, y: Int, n: Int)] = [:]
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let label = Int(mask.values[y * mask.width + x])
                let i = (y * mask.width + x) * 4
                if label == 0 {
                    tint[i + 3] = 150   // 배경 어둡게
                } else if let index = colorIndex[label] {
                    let (r, g, b) = overlayColors[index % overlayColors.count]
                    let alpha: CGFloat = 0.38
                    tint[i] = UInt8(r * alpha * 255)
                    tint[i + 1] = UInt8(g * alpha * 255)
                    tint[i + 2] = UInt8(b * alpha * 255)
                    tint[i + 3] = UInt8(alpha * 255)
                    let s = sums[label] ?? (0, 0, 0)
                    sums[label] = (s.x + x, s.y + y, s.n + 1)
                }
            }
        }
        if let provider = CGDataProvider(data: Data(tint) as CFData),
           let tintImage = CGImage(width: mask.width, height: mask.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: mask.width * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            context.interpolationQuality = .none
            context.draw(tintImage, in: rect)
        }

        // 번호 배지 (물체의 무게중심)
        let scaleX = Double(width) / Double(mask.width), scaleY = Double(height) / Double(mask.height)
        let fontSize = max(14, Double(min(width, height)) * 0.06)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        for (index, label) in labels.enumerated() {
            guard let s = sums[label], s.n > 0 else { continue }
            let center = CGPoint(x: Double(s.x) / Double(s.n) * scaleX,
                                 y: Double(height) - Double(s.y) / Double(s.n) * scaleY)
            let radius = fontSize * 0.85
            let (r, g, b) = overlayColors[index % overlayColors.count]
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.setStrokeColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
            context.setLineWidth(max(2, fontSize * 0.15))
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: circle)
            context.strokeEllipse(in: circle)

            let attributes: [CFString: Any] = [kCTFontAttributeName: font,
                                               kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)]
            let line = CTLineCreateWithAttributedString(
                CFAttributedStringCreate(nil, "\(label)" as CFString, attributes as CFDictionary))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            context.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
            CTLineDraw(line, context)
        }
        return try makeImage(context)
    }
}
