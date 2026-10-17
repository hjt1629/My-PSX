import CoreGraphics
import Foundation
import XCTest
@testable import PSXCore

final class HiggsfieldClientTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HiggsfieldTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        MockURLProtocol.handler = nil
    }

    private func makeClient(_ runner: FakeRunner) -> HiggsfieldClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return HiggsfieldClient(runner: runner, workRoot: root.appendingPathComponent("work"),
                                session: URLSession(configuration: configuration))
    }

    /// 배경 제거 모델이 돌려주는 투명 PNG를 내려받게 합니다.
    private func serveTransparentResult() throws {
        let png = try ImageEncoding.pngData(TestImages.transparent(width: 40, height: 40))
        MockURLProtocol.handler = { request, _ in
            XCTAssertEqual(request.url?.absoluteString, "https://cdn.higgsfield.ai/jobs/abc/result.png")
            return (200, png)
        }
    }

    func testRemoveBackgroundUsesRemoverModelAndFillsWhite() async throws {
        try serveTransparentResult()
        let runner = FakeRunner { arguments, directory in
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("input.png").path))
            return CommandResult(status: 0, output: #"{"id":"abc","status":"completed","result_url":"https:\/\/cdn.higgsfield.ai\/jobs\/abc\/result.png"}"#)
        }
        let original = TestImages.solid(width: 40, height: 40, gray: 0.3)
        let result = try await makeClient(runner).removeBackground(original, transparent: false)

        let arguments = try XCTUnwrap(runner.calls.first?.arguments)
        XCTAssertEqual(Array(arguments.prefix(5)),
                       ["higgsfield", "generate", "create", "image_background_remover", "--image"])
        XCTAssertTrue(arguments[5].hasSuffix("/input.png"))
        XCTAssertTrue(arguments.contains("--wait"))
        XCTAssertTrue(arguments.contains("--json"))
        XCTAssertFalse(arguments.contains("--prompt"))
        // 흰 배경을 원하면 투명 부분을 채워 불투명하게
        XCTAssertFalse(result.hasAlpha)
        XCTAssertEqual(result.width, 40)
    }

    func testRemoveBackgroundKeepsTransparency() async throws {
        try serveTransparentResult()
        let runner = FakeRunner { _, _ in
            CommandResult(status: 0, output: "Job completed\nhttps://cdn.higgsfield.ai/jobs/abc/result.png\n")
        }
        let result = try await makeClient(runner).removeBackground(TestImages.solid(width: 40, height: 40, gray: 0.3),
                                                                   transparent: true)
        XCTAssertTrue(result.hasAlpha)
    }

    func testEditUsesGPTImageWithPrompt() async throws {
        try serveTransparentResult()
        let runner = FakeRunner { _, _ in
            CommandResult(status: 0, output: #"{"result_url":"https://cdn.higgsfield.ai/jobs/abc/result.png"}"#)
        }
        _ = try await makeClient(runner).edit(TestImages.solid(width: 40, height: 40, gray: 0.3),
                                              prompt: "배경을 하늘색으로", transparentBackground: false)
        let arguments = try XCTUnwrap(runner.calls.first?.arguments)
        XCTAssertEqual(arguments[3], "gpt_image_2_5")
        let promptIndex = try XCTUnwrap(arguments.firstIndex(of: "--prompt"))
        XCTAssertEqual(arguments[promptIndex + 1], "배경을 하늘색으로")
        let backgroundIndex = try XCTUnwrap(arguments.firstIndex(of: "--background"))
        XCTAssertEqual(arguments[backgroundIndex + 1], "opaque")
    }

    func testResultURLPrefersResultField() {
        let output = """
            Uploading https://cdn.higgsfield.ai/uploads/input.png
            {"result_url": "https://cdn.higgsfield.ai/jobs/1/out.webp"}
            """
        XCTAssertEqual(HiggsfieldClient.resultURL(in: output)?.absoluteString, "https://cdn.higgsfield.ai/jobs/1/out.webp")
        XCTAssertNil(HiggsfieldClient.resultURL(in: "no links here"))
    }

    func testErrors() async {
        await assertThrows(FakeRunner { _, _ in CommandResult(status: 127, output: "zsh:1: command not found: higgsfield") },
                           .notInstalled)
        await assertThrows(FakeRunner { _, _ in CommandResult(status: 0, output: "completed, but nothing to show") },
                           .noImage("completed, but nothing to show"))
        let runner = FakeRunner { _, _ in CommandResult(status: 1, output: "Error: not authenticated. Run `higgsfield auth login`.") }
        do {
            _ = try await makeClient(runner).removeBackground(TestImages.solid(width: 8, height: 8, gray: 0.5), transparent: false)
            XCTFail("오류가 나야 합니다")
        } catch let error as HiggsfieldError {
            guard case .notLoggedIn = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    private func assertThrows(_ runner: FakeRunner, _ expected: HiggsfieldError,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await makeClient(runner).removeBackground(TestImages.solid(width: 8, height: 8, gray: 0.5),
                                                              transparent: false)
            XCTFail("오류가 나야 합니다", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? HiggsfieldError, expected, file: file, line: line)
        }
    }
}
