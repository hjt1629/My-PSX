import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PSXCore

final class ImageOpsTests: XCTestCase {
    typealias RGB = (UInt8, UInt8, UInt8)
    let red: RGB = (255, 0, 0)
    let blue: RGB = (0, 0, 255)
    let green: RGB = (0, 255, 0)
    let white: RGB = (255, 255, 255)

    // MARK: 회전 / 반전

    func testRotateClockwiseMovesLeftSideToTop() throws {
        // 가로 2px: [빨강, 파랑]
        let image = makeImage(width: 2, height: 1, pixels: [red, blue])
        let rotated = try ImageOps.rotate(image, clockwise: true)
        XCTAssertEqual(rotated.width, 1)
        XCTAssertEqual(rotated.height, 2)
        assertPixel(rotated, x: 0, y: 0, equals: red)
        assertPixel(rotated, x: 0, y: 1, equals: blue)
    }

    func testRotateCounterClockwiseMovesLeftSideToBottom() throws {
        let image = makeImage(width: 2, height: 1, pixels: [red, blue])
        let rotated = try ImageOps.rotate(image, clockwise: false)
        XCTAssertEqual(rotated.width, 1)
        XCTAssertEqual(rotated.height, 2)
        assertPixel(rotated, x: 0, y: 0, equals: blue)
        assertPixel(rotated, x: 0, y: 1, equals: red)
    }

    func testFlipHorizontal() throws {
        let image = makeImage(width: 2, height: 1, pixels: [red, blue])
        let flipped = try ImageOps.flip(image, horizontal: true)
        assertPixel(flipped, x: 0, y: 0, equals: blue)
        assertPixel(flipped, x: 1, y: 0, equals: red)
    }

    func testFlipVertical() throws {
        let image = makeImage(width: 1, height: 2, pixels: [red, blue])
        let flipped = try ImageOps.flip(image, horizontal: false)
        assertPixel(flipped, x: 0, y: 0, equals: blue)
        assertPixel(flipped, x: 0, y: 1, equals: red)
    }

    // MARK: 자르기 / 크기 조절

    func testCropUsesTopLeftOrigin() throws {
        // 2x2: 위 [빨강, 파랑], 아래 [초록, 흰색]
        let image = makeImage(width: 2, height: 2, pixels: [red, blue, green, white])
        let cropped = try ImageOps.crop(image, to: CGRect(x: 1, y: 0, width: 1, height: 1))
        XCTAssertEqual(cropped.width, 1)
        XCTAssertEqual(cropped.height, 1)
        assertPixel(cropped, x: 0, y: 0, equals: blue)

        let bottomLeft = try ImageOps.crop(image, to: CGRect(x: 0, y: 1, width: 1, height: 1))
        assertPixel(bottomLeft, x: 0, y: 0, equals: green)
    }

    func testCropOutsideImageIsClamped() throws {
        let image = makeImage(width: 2, height: 2, pixels: [red, blue, green, white])
        let cropped = try ImageOps.crop(image, to: CGRect(x: 1, y: 1, width: 10, height: 10))
        XCTAssertEqual(cropped.width, 1)
        XCTAssertEqual(cropped.height, 1)
        assertPixel(cropped, x: 0, y: 0, equals: white)
    }

    func testCropEmptyRectThrows() {
        let image = makeImage(width: 2, height: 2, pixels: [red, blue, green, white])
        XCTAssertThrowsError(try ImageOps.crop(image, to: CGRect(x: 5, y: 5, width: 1, height: 1)))
    }

    func testResize() throws {
        let image = makeImage(width: 4, height: 2, pixels: Array(repeating: red, count: 8))
        let resized = try ImageOps.resize(image, width: 8, height: 4)
        XCTAssertEqual(resized.width, 8)
        XCTAssertEqual(resized.height, 4)
        assertPixel(resized, x: 3, y: 2, equals: red)
    }

    func testOpaqueImageStaysOpaqueAfterEditing() throws {
        let image = makeImage(width: 2, height: 1, pixels: [red, blue])
        XCTAssertFalse(image.hasAlpha)
        XCTAssertFalse(try ImageOps.rotate(image, clockwise: true).hasAlpha)
        XCTAssertFalse(try ImageOps.resize(image, width: 4, height: 2).hasAlpha)
    }

    // MARK: 저장

    func testWritePNGAndReadBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("test.png")
        let image = makeImage(width: 2, height: 1, pixels: [red, blue])
        try ImageExporter.write(image, to: url, metadataFrom: nil)
        // 덮어쓰기도 동작해야 합니다.
        let rotated = try ImageOps.rotate(image, clockwise: true)
        try ImageExporter.write(rotated, to: url, metadataFrom: url)

        let loaded = try ImageLoader.loadFullImage(url)
        XCTAssertEqual(loaded.width, 1)
        XCTAssertEqual(loaded.height, 2)
        assertPixel(loaded, x: 0, y: 0, equals: red)
        XCTAssertEqual(ImageLoader.pixelSize(of: url), CGSize(width: 1, height: 2))
        XCTAssertNil(ImageLoader.pixelSize(of: directory.appendingPathComponent("missing.png")))

        // 임시 파일이 남아 있으면 안 됩니다.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["test.png"])
    }

    func testLargestLabelPicksBiggestObjectAndIgnoresBackground() {
        var counts = [Int](repeating: 0, count: 256)
        counts[0] = 10_000   // 배경
        counts[1] = 120      // 아이콘
        counts[2] = 5_000    // 상품
        counts[3] = 300      // 글자
        XCTAssertEqual(ImageOps.largestLabel(counts: counts, among: IndexSet([1, 2, 3])), 2)
        XCTAssertEqual(ImageOps.largestLabel(counts: counts, among: IndexSet([1, 3])), 3)
        XCTAssertNil(ImageOps.largestLabel(counts: counts, among: IndexSet()))
    }

    func testSupportedImageDetection() {
        XCTAssertTrue(ImageLoader.isSupportedImage(URL(fileURLWithPath: "/a/photo.JPG")))
        XCTAssertTrue(ImageLoader.isSupportedImage(URL(fileURLWithPath: "/a/photo.heic")))
        XCTAssertTrue(ImageLoader.isSupportedImage(URL(fileURLWithPath: "/a/photo.png")))
        XCTAssertFalse(ImageLoader.isSupportedImage(URL(fileURLWithPath: "/a/notes.txt")))
        XCTAssertFalse(ImageLoader.isSupportedImage(URL(fileURLWithPath: "/a/icon.svg")))
    }

    // MARK: 도우미

    /// pixels는 왼쪽 위부터 한 줄씩
    private func makeImage(width: Int, height: Int, pixels: [RGB]) -> CGImage {
        precondition(pixels.count == width * height)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for (i, pixel) in pixels.enumerated() {
            bytes[i * 4] = pixel.0
            bytes[i * 4 + 1] = pixel.1
            bytes[i * 4 + 2] = pixel.2
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGB {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // 비트맵 메모리의 첫 줄이 이미지의 맨 위 줄입니다.
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    private func assertPixel(_ image: CGImage, x: Int, y: Int, equals expected: RGB,
                             file: StaticString = #filePath, line: UInt = #line) {
        let actual = pixel(image, x: x, y: y)
        let close = abs(Int(actual.0) - Int(expected.0)) <= 2
            && abs(Int(actual.1) - Int(expected.1)) <= 2
            && abs(Int(actual.2) - Int(expected.2)) <= 2
        XCTAssertTrue(close, "(\(x), \(y)) 픽셀: 기대 \(expected), 실제 \(actual)", file: file, line: line)
    }
}
