import CoreGraphics
import CoreImage
import CoreML
import Foundation
import Vision

/// 편집 기능. 모든 함수는 원본을 바꾸지 않고 새 이미지를 반환합니다.
/// 좌표는 모두 픽셀 단위이며 원점은 왼쪽 위입니다.
public enum ImageOps {

    // MARK: 회전 / 반전

    public static func rotate(_ image: CGImage, clockwise: Bool) throws -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let context = try makeContext(width: image.height, height: image.width, like: image)
        if clockwise {
            context.translateBy(x: 0, y: w)
            context.rotate(by: -.pi / 2)
        } else {
            context.translateBy(x: h, y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return try makeImage(context)
    }

    public static func flip(_ image: CGImage, horizontal: Bool) throws -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let context = try makeContext(width: image.width, height: image.height, like: image)
        if horizontal {
            context.translateBy(x: w, y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: h)
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return try makeImage(context)
    }

    // MARK: 자르기 / 크기 조절

    public static func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let target = rect.integral.intersection(bounds)
        guard !target.isNull, target.width >= 1, target.height >= 1,
              let cropped = image.cropping(to: target) else {
            throw ImageError.renderFailed
        }
        return cropped
    }

    public static func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else { throw ImageError.renderFailed }
        let context = try makeContext(width: width, height: height, like: image)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try makeImage(context)
    }

    /// 투명한 부분을 배경색으로 채웁니다. (JPEG 저장용)
    public static func flatten(_ image: CGImage, background: CGColor = CGColor(gray: 1, alpha: 1)) throws -> CGImage {
        let context = try makeContext(width: image.width, height: image.height, like: image, alpha: false)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(background)
        context.fill(rect)
        context.draw(image, in: rect)
        return try makeImage(context)
    }

    // MARK: 배경 제거

    /// macOS 내장 Vision 프레임워크로 피사체만 남기고 배경을 투명하게 만듭니다.
    /// Neural Engine/GPU를 쓸 수 없는 환경(가상 머신 등)에서는 CPU로 다시 시도합니다.
    /// largestOnly: 찾은 물체 중 가장 큰 것(보통 상품)만 남기고, 아이콘·글자 같은 작은 물체는 지웁니다.
    public static func removeBackground(_ image: CGImage, largestOnly: Bool = false) throws -> CGImage {
        let segmentation = try ForegroundSegmentation(image)
        let keep = largestOnly ? segmentation.largest.map { [$0] } ?? segmentation.labels : segmentation.labels
        return try segmentation.cutout(keep)
    }

    // MARK: 내부 도우미

    static func makeContext(width: Int, height: Int, like image: CGImage, alpha: Bool? = nil) throws -> CGContext {
        let hasAlpha = alpha ?? image.hasAlpha
        let bitmapInfo = hasAlpha
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var candidates: [CGColorSpace] = []
        if let space = image.colorSpace, space.model == .rgb { candidates.append(space) }
        candidates.append(srgb)

        for space in candidates {
            if let context = CGContext(data: nil, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: 0,
                                       space: space, bitmapInfo: bitmapInfo) {
                context.interpolationQuality = .high
                return context
            }
        }
        throw ImageError.renderFailed
    }

    static func makeImage(_ context: CGContext) throws -> CGImage {
        guard let image = context.makeImage() else { throw ImageError.renderFailed }
        return image
    }
}
