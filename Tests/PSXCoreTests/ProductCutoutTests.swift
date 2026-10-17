import CoreGraphics
import Foundation
import XCTest
@testable import PSXCore

final class ProductCutoutTests: XCTestCase {
    // MARK: 답변 해석

    func testParseLabelsReadsJSONAndIgnoresUnknownNumbers() {
        XCTAssertEqual(ProductPickPrompt.parseLabels(#"{"keep":[2,3]}"#, valid: [1, 2, 3]), [2, 3])
        XCTAssertEqual(ProductPickPrompt.parseLabels("```json\n{\"keep\": [3, 9, 3]}\n```", valid: [1, 2, 3]), [3])
        XCTAssertEqual(ProductPickPrompt.parseLabels("Keep 1 and 3.", valid: [1, 2, 3]), [1, 3])
        XCTAssertEqual(ProductPickPrompt.parseLabels("none", valid: [1, 2]), [])
    }

    // MARK: 고르기

    func testChooseSkipsGPTWhenThereIsOnlyOneObject() async throws {
        let picker = FakePicker(answer: [9])
        let keep = try await ProductCutout.choose(labels: [1], areas: [1: 10],
                                                  overlay: { TestImages.solid(width: 2, height: 2, gray: 0) },
                                                  picker: picker)
        XCTAssertEqual(keep, [1])
        XCTAssertEqual(picker.calls, 0)
    }

    func testChooseUsesGPTAnswer() async throws {
        let picker = FakePicker(answer: [3, 1, 7])
        let keep = try await ProductCutout.choose(labels: [1, 2, 3], areas: [1: 10, 2: 500, 3: 20],
                                                  overlay: { TestImages.solid(width: 2, height: 2, gray: 0) },
                                                  picker: picker)
        XCTAssertEqual(keep, [1, 3])
        XCTAssertEqual(picker.calls, 1)
        XCTAssertEqual(picker.labels, [1, 2, 3])
    }

    func testChooseFallsBackToLargestObject() async throws {
        let picker = FakePicker(answer: [])
        let keep = try await ProductCutout.choose(labels: [1, 2, 3], areas: [1: 10, 2: 500, 3: 20],
                                                  overlay: { TestImages.solid(width: 2, height: 2, gray: 0) },
                                                  picker: picker)
        XCTAssertEqual(keep, [2])
    }

    // MARK: 번호 표시 사진

    func testOverlayDarkensBackgroundAndTintsObjects() throws {
        // 왼쪽 절반은 물체 1, 오른쪽 절반은 배경
        let photo = TestImages.solid(width: 200, height: 100, gray: 0.8)
        var values = [UInt8](repeating: 0, count: 40 * 20)
        for y in 0..<20 { for x in 0..<20 { values[y * 40 + x] = 1 } }
        let mask = LabelMap(width: 40, height: 20, values: values)
        XCTAssertEqual(mask.areas(of: [1]), [1: 400])

        let overlay = try ImageOps.makeOverlay(photo: photo, mask: mask, labels: [1], maxPixelSize: 100)
        XCTAssertEqual(overlay.width, 100)
        XCTAssertEqual(overlay.height, 50)
        let background = TestImages.pixel(overlay, x: 90, y: 25)
        let object = TestImages.pixel(overlay, x: 5, y: 5)
        let original = TestImages.pixel(photo)
        XCTAssertLessThan(background.0, original.0 - 60)           // 배경은 어둡게
        XCTAssertGreaterThan(Int(object.0), Int(object.2) + 20)     // 물체 1은 빨간빛
    }

    // MARK: OpenAI

    override func tearDown() {
        MockURLProtocol.handler = nil
    }

    private func makeOpenAIPicker(model: String = "gpt-5-mini") -> OpenAIProductPicker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return OpenAIProductPicker(apiKey: "sk-test", model: model, session: URLSession(configuration: configuration))
    }

    func testOpenAIPickerSendsSmallImageAndReadsAnswer() async throws {
        var sent: [String: Any] = [:]
        MockURLProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            sent = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let response = #"{"output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"{\"keep\":[2]}"}]}]}"#
            return (200, Data(response.utf8))
        }
        let picked = try await makeOpenAIPicker().pickProduct(in: TestImages.solid(width: 8, height: 8, gray: 0.5),
                                                              labels: [1, 2])
        XCTAssertEqual(picked, [2])
        XCTAssertEqual(sent["model"] as? String, "gpt-5-mini")
        XCTAssertEqual((sent["reasoning"] as? [String: Any])?["effort"] as? String, "minimal")
        let input = sent["input"] as? [[String: Any]]
        let content = input?.first?["content"] as? [[String: Any]]
        let image = content?.first { $0["type"] as? String == "input_image" }
        XCTAssertTrue((image?["image_url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    func testOpenAIPickerRetriesWhenReasoningEffortIsRejected() async throws {
        var efforts: [String?] = []
        MockURLProtocol.handler = { _, body in
            let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let effort = (json["reasoning"] as? [String: Any])?["effort"] as? String
            efforts.append(effort)
            if effort == "minimal" {
                return (400, Data(#"{"error":{"message":"Unsupported value: 'reasoning.effort' does not support 'minimal'."}}"#.utf8))
            }
            return (200, Data(#"{"output_text":"{\"keep\":[1]}"}"#.utf8))
        }
        let picked = try await makeOpenAIPicker().pickProduct(in: TestImages.solid(width: 8, height: 8, gray: 0.5),
                                                              labels: [1, 2])
        XCTAssertEqual(picked, [1])
        XCTAssertEqual(efforts, ["minimal", "none"])
    }

    func testNonReasoningModelSendsNoReasoningField() {
        XCTAssertEqual(OpenAIProductPicker.reasoningEfforts(for: "gpt-4.1-mini"), [nil])
    }

    // MARK: Codex

    func testCodexPickerReadsLastMessageFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeRunner { arguments, directory in
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("objects.jpg").path))
            let answerIndex = try XCTUnwrap(arguments.firstIndex(of: "-o"))
            try #"{"keep":[3]}"#.write(toFile: arguments[answerIndex + 1], atomically: true, encoding: .utf8)
            return CommandResult(status: 0, output: "lots of codex logs 1 2")
        }
        let client = CodexImageClient(runner: runner, codexHome: root.appendingPathComponent("home"),
                                      workRoot: root.appendingPathComponent("work"))
        let picked = try await client.pickProduct(in: TestImages.solid(width: 8, height: 8, gray: 0.5), labels: [1, 2, 3])
        XCTAssertEqual(picked, [3])

        let arguments = try XCTUnwrap(runner.calls.first?.arguments)
        XCTAssertEqual(Array(arguments.prefix(5)), ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only"])
        XCTAssertTrue(arguments.contains("--image"))
        XCTAssertFalse(arguments.contains("--full-auto"))
        XCTAssertNil(runner.calls.first?.environment["OPENAI_API_KEY"])
    }
}

private final class FakePicker: AIProductPicker, @unchecked Sendable {
    let answer: [Int]
    private(set) var calls = 0
    private(set) var labels: [Int] = []

    init(answer: [Int]) { self.answer = answer }

    func pickProduct(in overlay: CGImage, labels: [Int]) async throws -> [Int] {
        calls += 1
        self.labels = labels
        return answer
    }
}
