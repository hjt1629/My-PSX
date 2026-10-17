import CoreGraphics
import Foundation
import XCTest
@testable import PSXCore

final class AdjustmentTests: XCTestCase {
    func testIdentityReturnsSameImage() throws {
        let image = TestImages.solid(width: 4, height: 4, gray: 0.5)
        XCTAssertTrue(try ImageOps.adjust(image, ImageAdjustments()) === image)
    }

    func testBrightnessMakesImageBrighter() throws {
        let image = TestImages.solid(width: 4, height: 4, gray: 0.5)
        let brighter = try ImageOps.adjust(image, ImageAdjustments(brightness: 100))
        let darker = try ImageOps.adjust(image, ImageAdjustments(brightness: -100))
        XCTAssertGreaterThan(TestImages.pixel(brighter).0, TestImages.pixel(image).0 + 10)
        XCTAssertLessThan(TestImages.pixel(darker).0, TestImages.pixel(image).0 - 10)
    }

    func testSaturationMinusHundredMakesGray() throws {
        let image = TestImages.color(width: 4, height: 4, red: 0.9, green: 0.2, blue: 0.1)
        let gray = try ImageOps.adjust(image, ImageAdjustments(saturation: -100))
        let (r, g, b) = TestImages.pixel(gray)
        XCTAssertLessThan(abs(Int(r) - Int(g)), 4)
        XCTAssertLessThan(abs(Int(g) - Int(b)), 4)
    }

    func testContrastSpreadsValues() throws {
        let light = TestImages.solid(width: 4, height: 4, gray: 0.75)
        let more = try ImageOps.adjust(light, ImageAdjustments(contrast: 100))
        XCTAssertGreaterThan(TestImages.pixel(more).0, TestImages.pixel(light).0)
    }

    func testAdjustKeepsOpaqueImagesOpaqueAndSize() throws {
        let image = TestImages.solid(width: 7, height: 3, gray: 0.5)
        let result = try ImageOps.adjust(image, ImageAdjustments(brightness: 30, contrast: 20, saturation: 10))
        XCTAssertFalse(result.hasAlpha)
        XCTAssertEqual(result.width, 7)
        XCTAssertEqual(result.height, 3)
    }

    func testDownscaled() throws {
        let image = TestImages.solid(width: 400, height: 200, gray: 0.5)
        let small = try ImageOps.downscaled(image, maxPixelSize: 100)
        XCTAssertEqual(small.width, 100)
        XCTAssertEqual(small.height, 50)
        XCTAssertTrue(try ImageOps.downscaled(image, maxPixelSize: 1000) === image)
    }
}

final class OpenAIImageClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
    }

    private func makeClient() -> OpenAIImageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return OpenAIImageClient(apiKey: "sk-test", model: "gpt-image-1.5",
                                 session: URLSession(configuration: configuration))
    }

    private func successBody(width: Int, height: Int, alpha: Bool) throws -> Data {
        let image = alpha
            ? TestImages.transparent(width: width, height: height)
            : TestImages.solid(width: width, height: height, gray: 0.3)
        let base64 = try ImageEncoding.pngData(image).base64EncodedString()
        return Data(#"{"created":1,"data":[{"b64_json":"\#(base64)"}]}"#.utf8)
    }

    func testEditSendsMultipartRequestAndDecodesResult() async throws {
        var captured: (URLRequest, Data)?
        let body = try successBody(width: 64, height: 64, alpha: false)
        MockURLProtocol.handler = { request, requestBody in
            captured = (request, requestBody)
            return (200, body)
        }

        let original = TestImages.solid(width: 100, height: 100, gray: 0.6)
        let result = try await makeClient().edit(original, prompt: "make it brighter")

        let (request, requestBody) = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/edits")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

        let text = String(decoding: requestBody, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\ngpt-image-1.5\r\n"))
        XCTAssertTrue(text.contains("name=\"prompt\"\r\n\r\nmake it brighter\r\n"))
        XCTAssertTrue(text.contains("name=\"size\"\r\n\r\n1024x1024\r\n"))
        XCTAssertTrue(text.contains("name=\"image\"; filename=\"image.png\""))
        XCTAssertFalse(text.contains("name=\"background\""))

        // 같은 비율이면 원본 크기로 맞추고, 원본이 불투명하면 결과도 불투명
        XCTAssertEqual(result.width, 100)
        XCTAssertEqual(result.height, 100)
        XCTAssertFalse(result.hasAlpha)
    }

    func testTransparentBackgroundRequestKeepsAlpha() async throws {
        var bodyText = ""
        let body = try successBody(width: 64, height: 64, alpha: true)
        MockURLProtocol.handler = { _, requestBody in
            bodyText = String(decoding: requestBody, as: UTF8.self)
            return (200, body)
        }
        let original = TestImages.solid(width: 50, height: 50, gray: 0.6)
        let result = try await makeClient().edit(original, prompt: "remove bg", transparentBackground: true)
        XCTAssertTrue(bodyText.contains("name=\"background\"\r\n\r\ntransparent\r\n"))
        XCTAssertTrue(result.hasAlpha)
    }

    func testUnauthorizedError() async {
        MockURLProtocol.handler = { _, _ in (401, Data(#"{"error":{"message":"bad key"}}"#.utf8)) }
        do {
            _ = try await makeClient().edit(TestImages.solid(width: 8, height: 8, gray: 0.5), prompt: "x")
            XCTFail("오류가 나야 합니다")
        } catch {
            XCTAssertEqual(error as? GPTError, .unauthorized)
        }
    }

    func testAPIErrorMessageIsShown() async {
        MockURLProtocol.handler = { _, _ in
            (400, Data(#"{"error":{"message":"Transparent background is not supported for this model."}}"#.utf8))
        }
        do {
            _ = try await makeClient().edit(TestImages.solid(width: 8, height: 8, gray: 0.5), prompt: "x",
                                            transparentBackground: true)
            XCTFail("오류가 나야 합니다")
        } catch {
            XCTAssertEqual(error as? GPTError,
                           .api(status: 400, message: "Transparent background is not supported for this model."))
            XCTAssertTrue(error.localizedDescription.contains("400"))
        }
    }

    func testMissingKey() async {
        let client = OpenAIImageClient(apiKey: "")
        do {
            try await client.checkConnection()
            XCTFail("오류가 나야 합니다")
        } catch {
            XCTAssertEqual(error as? GPTError, .missingKey)
        }
    }

    func testCheckConnectionUsesModelEndpoint() async throws {
        var url: URL?
        MockURLProtocol.handler = { request, _ in
            url = request.url
            return (200, Data(#"{"id":"gpt-image-1.5"}"#.utf8))
        }
        try await makeClient().checkConnection()
        XCTAssertEqual(url?.absoluteString, "https://api.openai.com/v1/models/gpt-image-1.5")
    }

    func testRequestSizeFollowsAspect() {
        XCTAssertEqual(OpenAIImageClient.requestSize(for: CGSize(width: 4000, height: 3000)), "1536x1024")
        XCTAssertEqual(OpenAIImageClient.requestSize(for: CGSize(width: 3000, height: 4000)), "1024x1536")
        XCTAssertEqual(OpenAIImageClient.requestSize(for: CGSize(width: 1000, height: 1000)), "1024x1024")
    }

    func testDifferentAspectResultIsNotStretched() throws {
        let result = TestImages.solid(width: 1536, height: 1024, gray: 0.5)
        let original = TestImages.solid(width: 1000, height: 500, gray: 0.5)
        let fitted = try OpenAIImageClient.fitResult(result, to: original, keepTransparency: false)
        XCTAssertEqual(fitted.width, 1536)
        XCTAssertEqual(fitted.height, 1024)
    }
}

/// 실제 네트워크 대신 정해 둔 응답을 돌려줍니다.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request, Self.body(of: request))
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession은 본문을 스트림으로 바꿔 넘기므로 직접 읽습니다.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

enum TestImages {
    static func solid(width: Int, height: Int, gray: CGFloat) -> CGImage {
        color(width: width, height: height, red: gray, green: gray, blue: gray)
    }

    static func color(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func transparent(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return context.makeImage()!
    }

    /// 가운데 픽셀의 RGB
    static func pixel(_ image: CGImage) -> (UInt8, UInt8, UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .none
            let x = CGFloat(image.width / 2), y = CGFloat(image.height / 2)
            context.draw(image, in: CGRect(x: -x, y: -y, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return (bytes[0], bytes[1], bytes[2])
    }
}
