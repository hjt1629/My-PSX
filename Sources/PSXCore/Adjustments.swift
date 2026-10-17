import CoreGraphics
import CoreImage
import Foundation

/// 밝기 / 대비 / 채도. 각 값은 -100 ~ 100이며 0이면 변화 없음.
public struct ImageAdjustments: Equatable, Sendable {
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double

    public init(brightness: Double = 0, contrast: Double = 0, saturation: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
    }

    public var isIdentity: Bool {
        brightness == 0 && contrast == 0 && saturation == 0
    }
}

extension ImageOps {
    /// 밝기 / 대비 / 채도를 조절합니다. 투명도 여부는 원본과 같게 유지합니다.
    public static func adjust(_ image: CGImage, _ adjustments: ImageAdjustments) throws -> CGImage {
        guard !adjustments.isIdentity else { return image }
        guard let filter = CIFilter(name: "CIColorControls") else { throw ImageError.renderFailed }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(adjustments.brightness / 100 * 0.25, forKey: kCIInputBrightnessKey)
        filter.setValue(1 + adjustments.contrast / 100 * 0.5, forKey: kCIInputContrastKey)
        filter.setValue(max(0, 1 + adjustments.saturation / 100), forKey: kCIInputSaturationKey)

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let output = filter.outputImage,
              let rendered = CIContext().createCGImage(output, from: rect) else {
            throw ImageError.renderFailed
        }
        let context = try makeContext(width: image.width, height: image.height, like: image)
        context.draw(rendered, in: rect)
        return try makeImage(context)
    }

    /// 긴 변이 maxPixelSize보다 크면 비율을 유지해 줄입니다.
    public static func downscaled(_ image: CGImage, maxPixelSize: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longest)
        return try resize(image,
                          width: max(1, Int((Double(image.width) * scale).rounded())),
                          height: max(1, Int((Double(image.height) * scale).rounded())))
    }
}
