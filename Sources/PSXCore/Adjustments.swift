import CoreGraphics
import CoreImage
import Foundation

/// 라이트룸 '기본' 패널과 비슷한 조정 값. 각 값은 -100 ~ 100(선명하게는 0 ~ 100)이며 0이면 변화 없음.
public struct ImageAdjustments: Equatable, Sendable {
    // 흰색 균형
    /// 색온도: + 따뜻하게(노랑), - 차갑게(파랑)
    public var temperature: Double
    /// 색조: + 자홍, - 초록
    public var tint: Double

    // 톤
    /// 노출: ±100 = ±2 스톱
    public var exposure: Double
    public var brightness: Double
    public var contrast: Double
    /// 밝은 영역
    public var highlights: Double
    /// 어두운 영역
    public var shadows: Double
    /// 흰색 계열
    public var whites: Double
    /// 검정 계열
    public var blacks: Double

    // 외관
    /// 부분 대비(Clarity)
    public var clarity: Double
    /// 생동감(Vibrance): 채도가 낮은 색 위주로 올립니다.
    public var vibrance: Double
    public var saturation: Double

    // 세부 / 효과
    /// 선명하게: 0 ~ 100
    public var sharpness: Double
    /// 비네팅: - 가장자리 어둡게, + 밝게
    public var vignette: Double

    public init(temperature: Double = 0, tint: Double = 0,
                exposure: Double = 0, brightness: Double = 0, contrast: Double = 0,
                highlights: Double = 0, shadows: Double = 0, whites: Double = 0, blacks: Double = 0,
                clarity: Double = 0, vibrance: Double = 0, saturation: Double = 0,
                sharpness: Double = 0, vignette: Double = 0) {
        self.temperature = temperature
        self.tint = tint
        self.exposure = exposure
        self.brightness = brightness
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.clarity = clarity
        self.vibrance = vibrance
        self.saturation = saturation
        self.sharpness = sharpness
        self.vignette = vignette
    }

    public var isIdentity: Bool { self == ImageAdjustments() }
}

extension ImageOps {
    /// 조정 값을 적용합니다. 크기와 투명도 여부는 원본과 같게 유지합니다.
    /// 반경이 있는 효과(부분 대비 등)는 이미지 크기에 비례해, 작은 미리보기와 원본의 결과가 같아 보입니다.
    public static func adjust(_ image: CGImage, _ a: ImageAdjustments) throws -> CGImage {
        guard !a.isIdentity else { return image }
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let scale = Double(min(image.width, image.height))
        var ci = source

        // 흰색 균형: R/G/B 비율 조절
        if a.temperature != 0 || a.tint != 0 {
            let t = a.temperature / 100 * 0.25
            let m = a.tint / 100 * 0.2
            ci = try apply("CIColorMatrix", to: ci, [
                "inputRVector": CIVector(x: 1 + t + m / 2, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 - m, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - t + m / 2, w: 0)
            ])
        }

        if a.exposure != 0 {
            ci = try apply("CIExposureAdjust", to: ci, [kCIInputEVKey: a.exposure / 100 * 2])
        }

        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            ci = try apply("CIColorControls", to: ci, [
                kCIInputBrightnessKey: a.brightness / 100 * 0.25,
                kCIInputContrastKey: 1 + a.contrast / 100 * 0.5,
                kCIInputSaturationKey: max(0, 1 + a.saturation / 100)
            ])
        }

        // 밝은 영역 / 어두운 영역 / 흰색 계열 / 검정 계열: 톤 곡선의 다섯 점을 움직입니다.
        if a.highlights != 0 || a.shadows != 0 || a.whites != 0 || a.blacks != 0 {
            let p0 = max(0, a.blacks / 100 * 0.15)
            let p4 = min(1, 1 + a.whites / 100 * 0.15)
            var p1 = 0.25 + a.shadows / 100 * 0.12 + min(0, a.blacks) / 100 * 0.06
            var p3 = 0.75 + a.highlights / 100 * 0.12 + max(0, a.whites) / 100 * 0.06
            p1 = min(max(p1, p0 + 0.02), 0.48)
            p3 = max(min(p3, p4 - 0.02), 0.52)
            ci = try apply("CIToneCurve", to: ci, [
                "inputPoint0": CIVector(x: 0, y: p0),
                "inputPoint1": CIVector(x: 0.25, y: p1),
                "inputPoint2": CIVector(x: 0.5, y: 0.5),
                "inputPoint3": CIVector(x: 0.75, y: p3),
                "inputPoint4": CIVector(x: 1, y: p4)
            ])
        }

        if a.vibrance != 0 {
            ci = try apply("CIVibrance", to: ci, ["inputAmount": a.vibrance / 100])
        }

        // 부분 대비: 큰 반경의 언샤프 마스크. 음수면 부드럽게.
        if a.clarity != 0 {
            ci = try apply("CIUnsharpMask", to: ci.clampedToExtent(), [
                kCIInputRadiusKey: max(1, scale * 0.02),
                kCIInputIntensityKey: a.clarity / 100 * 0.7
            ]).cropped(to: extent)
        }

        if a.sharpness > 0 {
            ci = try apply("CISharpenLuminance", to: ci.clampedToExtent(), [
                kCIInputSharpnessKey: a.sharpness / 100 * 0.8,
                kCIInputRadiusKey: max(1, scale * 0.0015)
            ]).cropped(to: extent)
        }

        if a.vignette != 0 {
            ci = try apply("CIVignetteEffect", to: ci, [
                kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                kCIInputRadiusKey: hypot(extent.width, extent.height) / 2 * 0.8,
                kCIInputIntensityKey: -a.vignette / 100,
                "inputFalloff": 0.6
            ])
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let rendered = CIContext().createCGImage(ci.cropped(to: extent), from: rect) else {
            throw ImageError.renderFailed
        }
        let context = try makeContext(width: image.width, height: image.height, like: image)
        context.draw(rendered, in: rect)
        return try makeImage(context)
    }

    private static func apply(_ name: String, to input: CIImage, _ parameters: [String: Any]) throws -> CIImage {
        guard let filter = CIFilter(name: name) else { throw ImageError.renderFailed }
        filter.setValue(input, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }
        guard let output = filter.outputImage else { throw ImageError.renderFailed }
        return output
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
