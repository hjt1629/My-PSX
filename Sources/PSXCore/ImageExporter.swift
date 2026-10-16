import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageExporter {
    /// 이 Mac에서 저장할 수 있는 형식인지 확인합니다.
    public static func canWrite(_ type: UTType) -> Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(type.identifier)
    }

    public static func canWrite(fileExtension: String) -> Bool {
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return canWrite(type)
    }

    /// 투명도를 저장할 수 있는 형식인지
    public static func supportsTransparency(_ type: UTType) -> Bool {
        type.conforms(to: .png) || type.conforms(to: .tiff) || type.conforms(to: .heic) || type.conforms(to: .gif)
    }

    /// 이미지를 저장합니다. 원본의 촬영 정보(EXIF, GPS 등)를 가능한 한 유지합니다.
    /// 임시 파일에 먼저 쓴 뒤 교체하므로 저장 도중 실패해도 원본이 손상되지 않습니다.
    public static func write(_ image: CGImage, to url: URL, metadataFrom source: URL?) throws {
        guard let type = UTType(filenameExtension: url.pathExtension), canWrite(type) else {
            throw ImageError.unsupportedFormat
        }

        var output = image
        if image.hasAlpha && !supportsTransparency(type) {
            output = try ImageOps.flatten(image)
        }

        let properties = metadata(from: source, for: type)
        let fileManager = FileManager.default
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageError.writeFailed
        }
        CGImageDestinationAddImage(destination, output, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: temporaryURL)
            throw ImageError.writeFailed
        }

        do {
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func metadata(from source: URL?, for type: UTType) -> [CFString: Any] {
        var result: [CFString: Any] = [:]
        if let source,
           let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            if var exif = original[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                // 크기가 바뀌었을 수 있으므로 원본 크기 정보는 버립니다.
                exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
                result[kCGImagePropertyExifDictionary] = exif
            }
            for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
                if let value = original[key] { result[key] = value }
            }
            if var tiff = original[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                result[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        // 회전은 이미 픽셀에 반영되어 있으므로 방향 정보는 "정방향"으로 저장합니다.
        result[kCGImagePropertyOrientation] = 1
        if type.conforms(to: .jpeg) || type.conforms(to: .heic) {
            result[kCGImageDestinationLossyCompressionQuality] = 0.92
        }
        return result
    }
}
