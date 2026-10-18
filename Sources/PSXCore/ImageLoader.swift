import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageLoader {
    /// 뷰어에서 보여줄 수 있는 이미지 파일인지 확인합니다.
    public static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .svg)
    }

    /// 썸네일을 만듭니다. EXIF 회전 정보가 적용된 상태로 반환됩니다.
    public static func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 픽셀 크기(가로 × 세로)를 이미지 전체를 읽지 않고 알아냅니다. 세로로 돌려 찍은 사진은 돌린 뒤의 크기입니다.
    public static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        // 5~8은 90도 회전이라 가로·세로가 바뀝니다.
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }

    /// 원본 해상도로 이미지를 불러옵니다. EXIF 회전 정보는 픽셀에 반영됩니다.
    public static func loadFullImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageError.cannotOpen
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0

        if orientation != 1, width > 0, height > 0 {
            // 원본 크기의 "썸네일"을 요청하면 ImageIO가 회전까지 적용해 줍니다.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height)
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return image
            }
        }

        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw ImageError.cannotOpen
        }
        return image
    }
}
