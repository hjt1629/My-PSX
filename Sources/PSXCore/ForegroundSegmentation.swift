import CoreGraphics
import CoreImage
import Foundation
import Vision

/// macOS Vision으로 사진 속 물체(인스턴스)를 찾아 오려 냅니다. ("맥 AI만" 배경 제거)
public final class ForegroundSegmentation: @unchecked Sendable {
    /// 물체 번호 (1부터)
    public let labels: [Int]
    /// 번호별 넓이(마스크 픽셀 수)
    public let areas: [Int: Int]

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
        mask = LabelMap(observation.instanceMask)
        labels = observation.allInstances.sorted()
        areas = mask.areas(of: labels)
    }

    /// 가장 넓은 물체 번호
    public var largest: Int? {
        labels.max { areas[$0, default: 0] < areas[$1, default: 0] }
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
