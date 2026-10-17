import CoreGraphics
import Foundation
import ImageIO

/// ChatGPT 구독으로 로그인한 Codex CLI(`codex exec`)에게 사진 수정을 맡깁니다.
///
/// - 맥에 Codex CLI가 설치되어 있고 `codex login`으로 ChatGPT 계정에 로그인되어 있어야 합니다.
/// - API 키 없이 구독의 Codex 사용량 안에서 동작합니다. (이미지는 글보다 사용량을 많이 씀)
/// - OpenAI가 공식으로 보장하는 연동 방식이 아니므로 Codex 업데이트에 따라 동작이 바뀔 수 있습니다.
public struct CodexImageClient: AIImageEditor {
    public var runner: CommandRunning
    /// Codex가 생성 이미지를 따로 저장하는 곳 (~/.codex)
    public var codexHome: URL
    /// 작업용 임시 폴더를 만들 위치
    public var workRoot: URL
    public var timeout: TimeInterval

    public init(runner: CommandRunning = LoginShellRunner(),
                codexHome: URL? = nil,
                workRoot: URL? = nil,
                timeout: TimeInterval = 600) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.runner = runner
        self.codexHome = codexHome
            ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        self.workRoot = workRoot
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MyPSX/codex", isDirectory: true)
        self.timeout = timeout
    }

    public var displayName: String { "ChatGPT 구독 (Codex CLI)" }

    /// Codex의 이미지 도구는 투명 배경을 만들지 못합니다.
    public var supportsTransparentBackground: Bool { false }

    static let inputName = "input.png"
    static let outputName = "output.png"

    public func edit(_ image: CGImage, prompt: String, transparentBackground: Bool) async throws -> CGImage {
        let fileManager = FileManager.default
        let directory = workRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let upload = try ImageOps.downscaled(image, maxPixelSize: 1536)
        try ImageEncoding.pngData(upload).write(to: directory.appendingPathComponent(Self.inputName))

        let started = Date()
        let result = try await runner.run(Self.arguments(directory: directory, prompt: prompt),
                                          in: directory,
                                          environment: Self.environment(),
                                          timeout: timeout)
        if result.timedOut { throw CodexError.timedOut }

        // 작업 폴더는 곧 지워지므로 파일을 메모리로 다 읽어 들인 뒤 해독합니다.
        guard let outputURL = Self.findOutput(in: directory, codexHome: codexHome, since: started),
              let data = try? Data(contentsOf: outputURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let output = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw CodexError.from(result)
        }
        return try AIResult.fit(output, to: image, keepTransparency: false)
    }

    /// `codex login status` 결과 (설치 / 로그인 확인용)
    public func loginStatus() async throws -> String {
        let directory = FileManager.default.temporaryDirectory
        let result = try await runner.run(["codex", "login", "status"], in: directory,
                                          environment: Self.environment(), timeout: 30)
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0 else { throw CodexError.from(result) }
        return text.isEmpty ? "로그인되어 있습니다." : text
    }

    // MARK: 도우미

    static func arguments(directory: URL, prompt: String) -> [String] {
        ["codex", "exec",
         "--skip-git-repo-check",
         // --full-auto 는 최신 Codex에서 없어졌습니다. exec 는 원래 승인을 묻지 않으므로 샌드박스만 지정합니다.
         "--sandbox", "workspace-write",
         // -i 는 여러 값을 받으므로 바로 뒤에 다른 옵션(-C)이 와야 지시문을 삼키지 않습니다.
         "--image", directory.appendingPathComponent(inputName).path,
         "-C", directory.path,
         instructions(for: prompt)]
    }

    /// Codex에게 줄 지시문. 이미지 도구로 input.png를 고쳐 output.png로 저장하게 합니다.
    static func instructions(for prompt: String) -> String {
        """
        Use your built-in image generation tool to edit the photo ./\(inputName) in the current directory.

        Edit request: \(prompt)

        Rules:
        - Use ./\(inputName) as the reference image and keep everything not mentioned in the request unchanged \
        (same subject, composition, framing, colors and details).
        - Save the final edited image as a PNG file at ./\(outputName) in the current directory.
        - Do not create, change or delete any other files.
        - When the file is saved, reply with only: DONE
        """
    }

    /// 구독으로 동작하도록 API 키 환경 변수는 넘기지 않습니다.
    static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OPENAI_API_KEY")
        return environment
    }

    /// 결과 이미지 찾기: ./output.png → 작업 폴더의 다른 새 이미지 → ~/.codex/generated_images 의 새 이미지
    static func findOutput(in directory: URL, codexHome: URL, since started: Date) -> URL? {
        let fileManager = FileManager.default
        let expected = directory.appendingPathComponent(outputName)
        if fileManager.fileExists(atPath: expected.path) { return expected }

        // 원본으로 넘긴 input.png는 결과가 아니므로 건너뜁니다.
        if let other = newestImage(under: directory, since: started, excludingName: inputName) { return other }
        return newestImage(under: codexHome.appendingPathComponent("generated_images"),
                           since: started.addingTimeInterval(-2), excludingName: nil)
    }

    private static func newestImage(under folder: URL, since started: Date, excludingName: String?) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return nil
        }
        var best: (url: URL, date: Date)?
        for case let url as URL in enumerator {
            guard ["png", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased()),
                  url.lastPathComponent != excludingName,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate, date >= started else { continue }
            if best == nil || date > best!.date { best = (url, date) }
        }
        return best?.url
    }
}

// MARK: - 상품 번호 고르기 (GPT 빠른 배경 제거)

extension CodexImageClient: AIProductPicker {
    static let overlayName = "objects.jpg"
    static let answerName = "answer.txt"

    /// 이미지를 만들지 않고 글 한 줄만 받으므로 이미지 수정보다 훨씬 빠릅니다.
    public func pickProduct(in overlay: CGImage, labels: [Int]) async throws -> [Int] {
        let fileManager = FileManager.default
        let directory = workRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try ImageEncoding.jpegData(overlay).write(to: directory.appendingPathComponent(Self.overlayName))

        let result = try await runner.run(Self.pickArguments(directory: directory, labels: labels),
                                          in: directory, environment: Self.environment(), timeout: 180)
        if result.timedOut { throw CodexError.timedOut }
        // -o 로 받은 마지막 답변 파일을 먼저 보고, 없으면 출력 전체에서 찾습니다.
        let answer = (try? String(contentsOf: directory.appendingPathComponent(Self.answerName), encoding: .utf8))
            ?? result.output
        let picked = ProductPickPrompt.parseLabels(answer, valid: labels)
        if picked.isEmpty && result.status != 0 { throw CodexError.from(result) }
        return picked
    }

    static func pickArguments(directory: URL, labels: [Int]) -> [String] {
        ["codex", "exec",
         "--skip-git-repo-check",
         "--sandbox", "read-only",
         // 짧게 생각하게 해서 응답을 빠르게
         "-c", "model_reasoning_effort=\"low\"",
         "--image", directory.appendingPathComponent(overlayName).path,
         "-o", directory.appendingPathComponent(answerName).path,
         "-C", directory.path,
         ProductPickPrompt.text(labels: labels) + "\nDo not run any commands or edit files; just answer."]
    }
}

public enum CodexError: LocalizedError, Equatable {
    case notInstalled
    case notLoggedIn(String)
    case timedOut
    case noImage(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Codex CLI를 찾을 수 없습니다. 터미널에서 'brew install codex' (또는 'npm install -g @openai/codex')로 설치한 뒤 'codex login'으로 ChatGPT 계정에 로그인해 주세요."
        case .notLoggedIn(let detail):
            return "Codex에 로그인되어 있지 않습니다. 터미널에서 'codex login'을 실행해 ChatGPT 계정으로 로그인해 주세요.\n\(detail)"
        case .timedOut:
            return "Codex가 너무 오래 응답하지 않아 중단했습니다. 잠시 뒤 다시 시도해 주세요."
        case .noImage(let detail):
            return "Codex가 이미지를 만들지 못했습니다.\n\(detail)"
        }
    }

    static func from(_ result: CommandResult) -> CodexError {
        let output = result.output
        let lower = output.lowercased()
        if result.status == 127 || lower.contains("command not found") || lower.contains("no such file or directory: codex") {
            return .notInstalled
        }
        let tail = Self.tail(of: output)
        if lower.contains("not logged in") || lower.contains("codex login") || lower.contains("401") {
            return .notLoggedIn(tail)
        }
        return .noImage(tail.isEmpty ? "(Codex 출력 없음, 종료 코드 \(result.status))" : tail)
    }

    /// 출력의 마지막 몇 줄
    static func tail(of output: String, lines: Int = 8) -> String {
        output.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(lines)
            .joined(separator: "\n")
    }
}

// MARK: - 명령 실행

public struct CommandResult: Sendable, Equatable {
    public var status: Int32
    public var output: String
    public var timedOut: Bool

    public init(status: Int32, output: String, timedOut: Bool = false) {
        self.status = status
        self.output = output
        self.timedOut = timedOut
    }
}

public protocol CommandRunning: Sendable {
    func run(_ arguments: [String], in directory: URL, environment: [String: String],
             timeout: TimeInterval) async throws -> CommandResult
}

/// 사용자의 로그인 셸(zsh -l)로 명령을 실행합니다.
/// Finder에서 연 앱은 터미널의 PATH를 모르기 때문에, 이렇게 해야 Homebrew / npm으로 설치한 codex를 찾습니다.
public struct LoginShellRunner: CommandRunning {
    public init() {}

    public func run(_ arguments: [String], in directory: URL, environment: [String: String],
                    timeout: TimeInterval) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // 인자는 따옴표 문제 없이 "$0" "$@"로 그대로 넘깁니다.
            process.arguments = ["-lc", "exec \"$0\" \"$@\""] + arguments
            process.currentDirectoryURL = directory
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            let deadline = DispatchTime.now() + timeout
            let timer = DispatchSource.makeTimerSource(queue: .global())
            let timedOut = TimedOutFlag()
            timer.schedule(deadline: deadline)
            timer.setEventHandler {
                if process.isRunning {
                    timedOut.set()
                    process.terminate()
                }
            }
            timer.resume()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            return CommandResult(status: process.terminationStatus,
                                 output: String(decoding: data, as: UTF8.self),
                                 timedOut: timedOut.value)
        }.value
    }
}

private final class TimedOutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
