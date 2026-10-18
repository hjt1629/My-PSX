import CoreGraphics
import Foundation
import XCTest
@testable import PSXCore

final class CodexImageClientTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeClient(_ runner: FakeRunner) -> CodexImageClient {
        CodexImageClient(runner: runner,
                         codexHome: root.appendingPathComponent("codex-home"),
                         workRoot: root.appendingPathComponent("work"))
    }

    func testRunsCodexExecAndReadsOutputPNG() async throws {
        let runner = FakeRunner { arguments, directory in
            // Codex가 할 일: input.png를 읽고 output.png를 씁니다.
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("input.png").path))
            try ImageEncoding.pngData(TestImages.solid(width: 32, height: 32, gray: 1))
                .write(to: directory.appendingPathComponent("output.png"))
            return CommandResult(status: 0, output: "DONE")
        }
        let original = TestImages.solid(width: 50, height: 50, gray: 0.2)
        let result = try await makeClient(runner).edit(original, prompt: "배경을 흰색으로", transparentBackground: false)

        let call = try XCTUnwrap(runner.calls.first)
        // 셸 명령이 필요 없어 읽기 전용, 진행 기록은 JSON, 생각 단계는 끔
        XCTAssertEqual(Array(call.arguments.prefix(8)),
                       ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only", "--json",
                        "-c", "model_reasoning_effort=\"none\""])
        XCTAssertFalse(call.arguments.contains("--full-auto"))
        XCTAssertEqual(call.arguments[8], "--image")
        XCTAssertTrue(call.arguments[9].hasSuffix("/input.png"))
        XCTAssertEqual(call.arguments[10], "-C")
        XCTAssertEqual(call.arguments[11], call.directory.path)
        let prompt = try XCTUnwrap(call.arguments.last)
        XCTAssertTrue(prompt.contains("배경을 흰색으로"))
        XCTAssertTrue(prompt.contains("image_gen"))
        XCTAssertTrue(prompt.contains(call.arguments[9]))           // referenced_image_paths
        XCTAssertTrue(prompt.contains("transparent_background: false"))
        XCTAssertNil(call.environment["OPENAI_API_KEY"])

        // 같은 비율이라 원본 크기로 맞춰지고, 작업 폴더는 지워집니다.
        XCTAssertEqual(result.width, 50)
        XCTAssertEqual(result.height, 50)
        XCTAssertFalse(FileManager.default.fileExists(atPath: call.directory.path))
    }

    func testFindsImageSavedUnderAnotherName() async throws {
        let runner = FakeRunner { _, directory in
            let nested = directory.appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try ImageEncoding.pngData(TestImages.solid(width: 20, height: 20, gray: 0.9))
                .write(to: nested.appendingPathComponent("edited.png"))
            return CommandResult(status: 0, output: "DONE")
        }
        let result = try await makeClient(runner).edit(TestImages.solid(width: 20, height: 20, gray: 0.1),
                                                       prompt: "x", transparentBackground: false)
        XCTAssertGreaterThan(TestImages.pixel(result).0, 200)
    }

    func testFindsImageInCodexGeneratedImages() async throws {
        let codexHome = root.appendingPathComponent("codex-home")
        let runner = FakeRunner { _, _ in
            let folder = codexHome.appendingPathComponent("generated_images/session-1", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try ImageEncoding.pngData(TestImages.solid(width: 20, height: 20, gray: 0.9))
                .write(to: folder.appendingPathComponent("img.png"))
            return CommandResult(status: 0, output: "DONE")
        }
        let result = try await makeClient(runner).edit(TestImages.solid(width: 20, height: 20, gray: 0.1),
                                                       prompt: "x", transparentBackground: false)
        XCTAssertGreaterThan(TestImages.pixel(result).0, 200)
    }

    func testReadsSavedPathFromJSONOutputAndKeepsTransparency() async throws {
        let saved = root.appendingPathComponent("somewhere/ig_1.png")
        try FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        let runner = FakeRunner { arguments, _ in
            XCTAssertTrue(arguments.last?.contains("transparent_background: true") == true)
            try ImageEncoding.pngData(TestImages.transparent(width: 20, height: 20)).write(to: saved)
            let escaped = saved.path.replacingOccurrences(of: "/", with: "\\/")
            return CommandResult(status: 0, output: """
                {"type":"thread.started"}
                {"type":"item.completed","item":{"type":"image_generation","saved_path":"\(escaped)"}}
                {"type":"turn.completed"}
                """)
        }
        let result = try await makeClient(runner).edit(TestImages.solid(width: 20, height: 20, gray: 0.5),
                                                       prompt: "x", transparentBackground: true)
        XCTAssertTrue(result.hasAlpha)
    }

    func testRetriesWithoutReasoningEffortWhenModelRejectsIt() async throws {
        let runner = FakeRunner { arguments, directory in
            if arguments.contains("model_reasoning_effort=\"none\"") {
                return CommandResult(status: 1, output: "ERROR: Unsupported value: 'none' is not supported for reasoning.effort")
            }
            try ImageEncoding.pngData(TestImages.solid(width: 10, height: 10, gray: 1))
                .write(to: directory.appendingPathComponent("output.png"))
            return CommandResult(status: 0, output: "DONE")
        }
        _ = try await makeClient(runner).edit(TestImages.solid(width: 10, height: 10, gray: 0.1),
                                              prompt: "x", transparentBackground: false)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertFalse(runner.calls[1].arguments.contains("-c"))
    }

    func testPrefersImageFromItsOwnThreadFolder() async throws {
        let codexHome = root.appendingPathComponent("codex-home")
        let runner = FakeRunner { _, _ in
            // 다른 작업이 더 늦게 만든 이미지가 있어도 이 실행(thread-A)의 이미지를 골라야 합니다.
            for (thread, gray) in [("thread-A", 0.9), ("thread-B", 0.1)] {
                let folder = codexHome.appendingPathComponent("generated_images/\(thread)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try ImageEncoding.pngData(TestImages.solid(width: 20, height: 20, gray: gray))
                    .write(to: folder.appendingPathComponent("ig.png"))
            }
            return CommandResult(status: 0, output: #"{"type":"thread.started","thread_id":"thread-A"}"#)
        }
        let result = try await makeClient(runner).edit(TestImages.solid(width: 20, height: 20, gray: 0.5),
                                                       prompt: "x", transparentBackground: false)
        XCTAssertGreaterThan(TestImages.pixel(result).0, 200)
    }

    func testNotInstalled() async {
        let runner = FakeRunner { _, _ in CommandResult(status: 127, output: "zsh:1: command not found: codex") }
        await assertThrows(makeClient(runner), CodexError.notInstalled)
    }

    func testNotLoggedIn() async {
        let runner = FakeRunner { _, _ in CommandResult(status: 1, output: "Error: Not logged in. Run codex login") }
        do {
            _ = try await makeClient(runner).edit(TestImages.solid(width: 8, height: 8, gray: 0.5),
                                                  prompt: "x", transparentBackground: false)
            XCTFail("오류가 나야 합니다")
        } catch let error as CodexError {
            guard case .notLoggedIn = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testNoImageShowsCodexOutput() async {
        let runner = FakeRunner { _, _ in CommandResult(status: 0, output: "line1\nYou've hit your usage limit.") }
        do {
            _ = try await makeClient(runner).edit(TestImages.solid(width: 8, height: 8, gray: 0.5),
                                                  prompt: "x", transparentBackground: false)
            XCTFail("오류가 나야 합니다")
        } catch {
            XCTAssertEqual(error as? CodexError, .noImage("line1\nYou've hit your usage limit."))
            XCTAssertTrue(error.localizedDescription.contains("usage limit"))
        }
    }

    func testTimedOut() async {
        let runner = FakeRunner { _, _ in CommandResult(status: 15, output: "", timedOut: true) }
        await assertThrows(makeClient(runner), CodexError.timedOut)
    }

    func testLoginStatus() async throws {
        let runner = FakeRunner { arguments, _ in
            XCTAssertEqual(arguments, ["codex", "login", "status"])
            return CommandResult(status: 0, output: "Logged in using ChatGPT\n")
        }
        let text = try await makeClient(runner).loginStatus()
        XCTAssertEqual(text, "Logged in using ChatGPT")
    }

    func testTransparentBackgroundSupport() {
        XCTAssertTrue(CodexImageClient().supportsTransparentBackground)
        XCTAssertTrue(OpenAIImageClient(apiKey: "k", model: "gpt-image-1.5").supportsTransparentBackground)
        XCTAssertFalse(OpenAIImageClient(apiKey: "k", model: "gpt-image-2").supportsTransparentBackground)
    }

    func testLoginShellRunnerRunsCommandsWithArguments() async throws {
        let result = try await LoginShellRunner().run(["printf", "%s|%s", "a b", "c\"d"],
                                                      in: root, environment: ProcessInfo.processInfo.environment,
                                                      timeout: 30)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.hasSuffix("a b|c\"d"), result.output)
    }

    func testLoginShellRunnerTimesOut() async throws {
        let result = try await LoginShellRunner().run(["sleep", "5"], in: root,
                                                      environment: ProcessInfo.processInfo.environment, timeout: 0.5)
        XCTAssertTrue(result.timedOut)
    }

    private func assertThrows(_ client: CodexImageClient, _ expected: CodexError,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client.edit(TestImages.solid(width: 8, height: 8, gray: 0.5),
                                      prompt: "x", transparentBackground: false)
            XCTFail("오류가 나야 합니다", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CodexError, expected, file: file, line: line)
        }
    }
}

/// codex 대신 정해 둔 동작을 하는 가짜 실행기
final class FakeRunner: CommandRunning, @unchecked Sendable {
    struct Call {
        let arguments: [String]
        let directory: URL
        let environment: [String: String]
    }

    private let handler: ([String], URL) throws -> CommandResult
    private let lock = NSLock()
    private var _calls: [Call] = []

    init(_ handler: @escaping ([String], URL) throws -> CommandResult) {
        self.handler = handler
    }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

    func run(_ arguments: [String], in directory: URL, environment: [String: String],
             timeout: TimeInterval) async throws -> CommandResult {
        lock.lock()
        _calls.append(Call(arguments: arguments, directory: directory, environment: environment))
        lock.unlock()
        return try handler(arguments, directory)
    }
}
