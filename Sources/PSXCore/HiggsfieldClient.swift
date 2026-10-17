import CoreGraphics
import Foundation
import ImageIO

/// Higgsfield 구독으로 로그인한 Higgsfield CLI(`higgsfield generate create`)로 배경을 지우고 사진을 수정합니다.
///
/// - 맥에 CLI가 설치되어 있고 `higgsfield auth login`으로 로그인되어 있어야 합니다.
/// - API 키 없이 구독 크레딧을 씁니다. (배경 제거 1장 ≈ 1크레딧)
/// - 배경 제거는 전용 모델(image_background_remover)이라 사진을 새로 그리지 않고, 상품은 원본 그대로입니다.
public struct HiggsfieldClient: AIImageEditor {
    public static let removerModel = "image_background_remover"
    public static let editModel = "gpt_image_2_5"

    public var runner: CommandRunning
    /// 작업용 임시 폴더를 만들 위치
    public var workRoot: URL
    public var session: URLSession
    public var timeout: TimeInterval

    public init(runner: CommandRunning = LoginShellRunner(),
                workRoot: URL? = nil,
                session: URLSession = .shared,
                timeout: TimeInterval = 600) {
        self.runner = runner
        self.workRoot = workRoot
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MyPSX/higgsfield", isDirectory: true)
        self.session = session
        self.timeout = timeout
    }

    public var displayName: String { "Higgsfield 구독 (CLI)" }
    public var supportsTransparentBackground: Bool { true }

    /// 배경 제거 전용 모델. 결과는 투명 배경이며, transparent가 아니면 흰색으로 채웁니다.
    public func removeBackground(_ image: CGImage, transparent: Bool) async throws -> CGImage {
        let output = try await generate(model: Self.removerModel, image: image, options: [])
        return try AIResult.fit(output, to: image, keepTransparency: transparent)
    }

    /// 글로 쓴 지시대로 수정 (GPT Image 2.5)
    public func edit(_ image: CGImage, prompt: String, transparentBackground: Bool) async throws -> CGImage {
        let output = try await generate(model: Self.editModel, image: image, options: [
            "--prompt", prompt,
            "--aspect_ratio", "auto",
            "--quality", "medium",
            "--background", transparentBackground ? "transparent" : "opaque"
        ])
        return try AIResult.fit(output, to: image, keepTransparency: transparentBackground)
    }

    /// `higgsfield account` 결과 (설치 / 로그인 / 남은 크레딧 확인용)
    public func accountStatus() async throws -> String {
        let result = try await runner.run(["higgsfield", "account"], in: FileManager.default.temporaryDirectory,
                                          environment: ProcessInfo.processInfo.environment, timeout: 30)
        guard result.status == 0 else { throw HiggsfieldError.from(result) }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "로그인되어 있습니다." : text
    }

    // MARK: 도우미

    private func generate(model: String, image: CGImage, options: [String]) async throws -> CGImage {
        let fileManager = FileManager.default
        let directory = workRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let input = directory.appendingPathComponent("input.png")
        try ImageEncoding.pngData(ImageOps.downscaled(image, maxPixelSize: 2048)).write(to: input)

        let result = try await runner.run(Self.arguments(model: model, input: input, options: options),
                                          in: directory, environment: ProcessInfo.processInfo.environment,
                                          timeout: timeout)
        if result.timedOut { throw HiggsfieldError.timedOut }
        guard result.status == 0 else { throw HiggsfieldError.from(result) }
        guard let url = Self.resultURL(in: result.output) else {
            throw HiggsfieldError.noImage(CodexError.tail(of: result.output))
        }

        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let output = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HiggsfieldError.noImage("결과 이미지를 받지 못했습니다: \(url.absoluteString)")
        }
        return output
    }

    static func arguments(model: String, input: URL, options: [String]) -> [String] {
        ["higgsfield", "generate", "create", model, "--image", input.path] + options
            + ["--wait", "--wait-interval", "1s", "--json"]
    }

    /// 출력에서 결과 이미지 주소를 찾습니다. ("result_url" → 없으면 마지막 https 이미지 주소)
    static func resultURL(in output: String) -> URL? {
        if let match = output.matches(of: #/"result_url"\s*:\s*"([^"]+)"/#).last {
            return URL(string: String(match.1).replacingOccurrences(of: "\\/", with: "/"))
        }
        let urls = output.matches(of: #/https://[^\s"'<>]+/#).map { String($0.output) }
        let images = urls.filter { url in
            ["png", "jpg", "jpeg", "webp"].contains { url.lowercased().contains(".\($0)") }
        }
        return (images.last ?? urls.last).flatMap(URL.init(string:))
    }
}

public enum HiggsfieldError: LocalizedError, Equatable {
    case notInstalled
    case notLoggedIn(String)
    case timedOut
    case noImage(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Higgsfield CLI를 찾을 수 없습니다. 터미널에서 'brew install higgsfield-ai/tap/higgsfield' (또는 'npm install -g @higgsfield/cli')로 설치한 뒤 'higgsfield auth login'으로 로그인해 주세요."
        case .notLoggedIn(let detail):
            return "Higgsfield에 로그인되어 있지 않습니다. 터미널에서 'higgsfield auth login'을 실행해 주세요.\n\(detail)"
        case .timedOut:
            return "Higgsfield가 너무 오래 응답하지 않아 중단했습니다. 잠시 뒤 다시 시도해 주세요."
        case .noImage(let detail):
            return "Higgsfield가 이미지를 만들지 못했습니다.\n\(detail)"
        }
    }

    static func from(_ result: CommandResult) -> HiggsfieldError {
        let lower = result.output.lowercased()
        if result.status == 127 || lower.contains("command not found") {
            return .notInstalled
        }
        let tail = CodexError.tail(of: result.output)
        if lower.contains("auth login") || lower.contains("not logged in") || lower.contains("unauthorized")
            || lower.contains("not authenticated") || lower.contains("401") {
            return .notLoggedIn(tail)
        }
        return .noImage(tail.isEmpty ? "(출력 없음, 종료 코드 \(result.status))" : tail)
    }
}
