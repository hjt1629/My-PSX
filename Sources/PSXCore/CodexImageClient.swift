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

    /// Codex의 이미지 도구(image_gen)는 transparent_background 옵션으로 투명 배경을 직접 만듭니다.
    public var supportsTransparentBackground: Bool { true }

    static let inputName = "input.png"
    static let outputName = "output.png"

    /// 생각 단계를 끄는 값. 모델이 받지 않으면 이 옵션 없이 한 번 더 실행합니다.
    static let fastReasoningEffort = "none"

    public func edit(_ image: CGImage, prompt: String, transparentBackground: Bool) async throws -> CGImage {
        let fileManager = FileManager.default
        let directory = workRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        // 작을수록 올리고 처리하는 시간이 줄어듭니다. 결과는 원본 크기로 다시 맞춥니다.
        let upload = try ImageOps.downscaled(image, maxPixelSize: 1024)
        try ImageEncoding.pngData(upload).write(to: directory.appendingPathComponent(Self.inputName))

        let started = Date()
        var result = try await run(directory: directory, prompt: prompt, transparent: transparentBackground,
                                   reasoningEffort: Self.fastReasoningEffort)
        if result.status != 0, Self.rejectedReasoningEffort(result.output) {
            result = try await run(directory: directory, prompt: prompt, transparent: transparentBackground,
                                   reasoningEffort: nil)
        }
        if result.timedOut { throw CodexError.timedOut }

        // 작업 폴더는 곧 지워지므로 파일을 메모리로 다 읽어 들인 뒤 해독합니다.
        let outputURL = Self.savedPath(in: result.output)
            ?? Self.findOutput(in: directory, codexHome: codexHome, since: started)
        guard let outputURL,
              let data = try? Data(contentsOf: outputURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let output = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw CodexError.from(result)
        }
        return try AIResult.fit(output, to: image, keepTransparency: transparentBackground)
    }

    private func run(directory: URL, prompt: String, transparent: Bool, reasoningEffort: String?) async throws -> CommandResult {
        try await runner.run(Self.arguments(directory: directory, prompt: prompt, transparent: transparent,
                                            reasoningEffort: reasoningEffort),
                             in: directory, environment: Self.environment(), timeout: timeout)
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

    static func arguments(directory: URL, prompt: String, transparent: Bool,
                          reasoningEffort: String? = fastReasoningEffort) -> [String] {
        var arguments = ["codex", "exec",
                         "--skip-git-repo-check",
                         // 셸 명령이 필요 없습니다. 이미지 도구는 결과를 ~/.codex/generated_images 에 저장합니다.
                         "--sandbox", "read-only",
                         // 진행 기록을 JSON으로 받아 저장된 이미지 경로(saved_path)를 바로 읽습니다.
                         "--json"]
        if let reasoningEffort {
            // 계획·검토 없이 바로 이미지 도구를 부르게 합니다 (가장 큰 시간 절약)
            arguments += ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""]
        }
        // -i 는 여러 값을 받으므로 바로 뒤에 다른 옵션(-C)이 와야 지시문을 삼키지 않습니다.
        arguments += ["--image", directory.appendingPathComponent(inputName).path,
                      "-C", directory.path,
                      instructions(for: prompt, input: directory.appendingPathComponent(inputName), transparent: transparent)]
        return arguments
    }

    /// Codex에게 줄 지시문. 다른 일 없이 이미지 도구를 바로 한 번만 부르게 합니다.
    static func instructions(for prompt: String, input: URL, transparent: Bool) -> String {
        """
        Call the built-in image_gen tool exactly once, immediately. Do not plan, explore, explain, \
        run shell commands, or create, copy or move any files.
        Tool arguments:
        - referenced_image_paths: ["\(input.path)"]
        - transparent_background: \(transparent)
        - prompt: Edit the referenced photo. \(prompt) Keep everything not mentioned unchanged \
        (same subject, composition, framing, colors and details).
        When the tool returns, reply with only: DONE
        """
    }

    /// `--json` 출력에서 이미지 도구가 저장한 파일 경로를 찾습니다.
    static func savedPath(in output: String) -> URL? {
        for match in output.matches(of: #/"saved_path"\s*:\s*"((?:[^"\\]|\\.)+)"/#).reversed() {
            let path = String(match.1).replacingOccurrences(of: "\\/", with: "/")
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// 모델이 reasoning effort 값을 받지 않아 실패했는지
    static func rejectedReasoningEffort(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("reasoning") && (lower.contains("unsupported") || lower.contains("not supported")
            || lower.contains("invalid") || lower.contains("does not support"))
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
