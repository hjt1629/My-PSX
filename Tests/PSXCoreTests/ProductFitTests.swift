import CoreGraphics
import Foundation
import XCTest
@testable import PSXCore

final class ProductFitTests: XCTestCase {
    /// 흰 바탕(200×100)의 x 120~159, y 20~59 (왼쪽 위 원점)에 빨간 상품
    private func productOnWhite() -> CGImage {
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        // CGContext는 왼쪽 아래 원점: 위에서 20 → 아래에서 100-20-40 = 40
        context.fill(CGRect(x: 120, y: 40, width: 40, height: 40))
        return context.makeImage()!
    }

    func testContentBoundsFindsProductOnWhite() throws {
        let bounds = try XCTUnwrap(ImageOps.contentBounds(productOnWhite()))
        XCTAssertEqual(bounds, CGRect(x: 120, y: 20, width: 40, height: 40))
        XCTAssertNil(ImageOps.contentBounds(TestImages.solid(width: 10, height: 10, gray: 1)))
    }

    func testContentBoundsUsesAlpha() throws {
        // 왼쪽 절반만 불투명
        let bounds = try XCTUnwrap(ImageOps.contentBounds(TestImages.transparent(width: 40, height: 20)))
        XCTAssertEqual(bounds, CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    func testFitToSquareCentersWithMargin() throws {
        let result = try ImageOps.fitToSquare(productOnWhite(), size: 100, margin: 0.1, transparent: false)
        XCTAssertEqual(result.width, 100)
        XCTAssertEqual(result.height, 100)
        XCTAssertFalse(result.hasAlpha)
        // 상품(40×40)이 80×80으로 커져 10~89에 놓임
        let bounds = try XCTUnwrap(ImageOps.contentBounds(result))
        XCTAssertEqual(bounds.minX, 10, accuracy: 1)
        XCTAssertEqual(bounds.minY, 10, accuracy: 1)
        XCTAssertEqual(bounds.width, 80, accuracy: 1)
        // 가장자리는 흰색, 가운데는 상품색
        XCTAssertEqual(TestImages.pixel(result, x: 2, y: 2).0, 255)
        XCTAssertLessThan(TestImages.pixel(result).1, 60)
    }

    func testFitToSquareKeepsTransparency() throws {
        let result = try ImageOps.fitToSquare(TestImages.transparent(width: 40, height: 20), size: 50,
                                              margin: 0, transparent: true)
        XCTAssertTrue(result.hasAlpha)
        XCTAssertEqual(result.width, 50)
    }

    func testPlaceDrawsAtTopLeftRectOnWhite() throws {
        let product = TestImages.solid(width: 40, height: 40, gray: 0.2)
        let result = try ImageOps.place(product, canvasWidth: 100, height: 100,
                                        at: CGRect(x: 10, y: 20, width: 30, height: 30))
        XCTAssertEqual(result.width, 100)
        XCTAssertFalse(result.hasAlpha)
        let bounds = try XCTUnwrap(ImageOps.contentBounds(result))
        XCTAssertEqual(bounds.minX, 10, accuracy: 1)
        XCTAssertEqual(bounds.minY, 20, accuracy: 1)
        XCTAssertEqual(bounds.width, 30, accuracy: 1)
        XCTAssertEqual(TestImages.pixel(result, x: 90, y: 90).0, 255)
    }

    func testPlaceClipsOutsideCanvas() throws {
        let product = TestImages.solid(width: 40, height: 40, gray: 0.2)
        let result = try ImageOps.place(product, canvasWidth: 100, height: 100,
                                        at: CGRect(x: -20, y: 80, width: 40, height: 40))
        let bounds = try XCTUnwrap(ImageOps.contentBounds(result))
        XCTAssertEqual(bounds, CGRect(x: 0, y: 80, width: 20, height: 20))
    }
}
