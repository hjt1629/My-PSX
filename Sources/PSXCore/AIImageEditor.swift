import CoreGraphics
import Foundation

/// 글로 사진을 수정해 주는 AI (OpenAI API 키 / ChatGPT 구독의 Codex CLI / Higgsfield 구독의 CLI)
public protocol AIImageEditor: Sendable {
    /// 화면에 보여줄 이름
    var displayName: String { get }
    /// 투명 배경 결과를 직접 만들 수 있는지
    var supportsTransparentBackground: Bool { get }
    /// - Parameter transparentBackground: true면 투명 배경 PNG를 요청합니다. (지원할 때만)
    func edit(_ image: CGImage, prompt: String, transparentBackground: Bool) async throws -> CGImage
    /// 상품만 남기고 배경을 흰색(transparent면 투명)으로. 기본 구현은 edit에 배경 정리 지시문을 줍니다.
    func removeBackground(_ image: CGImage, transparent: Bool) async throws -> CGImage
}

extension AIImageEditor {
    public func removeBackground(_ image: CGImage, transparent: Bool) async throws -> CGImage {
        if transparent && supportsTransparentBackground {
            return try await edit(image, prompt: AIPrompts.transparentBackground, transparentBackground: true)
        }
        let white = try await edit(image, prompt: AIPrompts.whiteBackground, transparentBackground: false)
        guard transparent else {
            return try white.hasAlpha ? ImageOps.flatten(white) : white
        }
        // 투명 배경을 직접 못 만드는 모델(gpt-image-2 API)만 흰 배경으로 정리한 뒤 macOS 기능으로 지웁니다.
        return try ImageOps.removeBackground(white)
    }
}

public enum AIPrompts {
    /// 상품만 남기는 규칙. 상품 위에 인쇄된 글자·로고는 상품의 일부라 그대로 둡니다.
    static let keepProductOnly =
        "This is a product photo. Keep ONLY the main product, exactly as it is: same shape, colors, "
        + "texture, details, position and size, including any text, labels or logos printed on the product itself. "
        + "Remove everything that is not part of the product: the background, icons, badges, stickers, "
        + "captions, overlaid text, prices, watermarks, logos and graphics placed around or over the photo, "
        + "props, decorations and other objects. "

    /// 상품만 남기고 나머지를 전부 흰색으로 — GPT 배경 제거의 기본 동작
    public static let whiteBackground = keepProductOnly
        + "Fill every removed area with a clean, solid, pure white (#FFFFFF). "
        + "Do not add shadows, reflections, text, borders or anything else."

    /// 상품만 남기고 나머지를 투명하게
    public static let transparentBackground = keepProductOnly
        + "Make every removed area fully transparent. Do not add anything."
}

enum AIResult {
    /// 결과의 비율이 원본과 거의 같으면 원본 크기로 맞춥니다.
    /// 투명 배경을 요청하지 않았고 원본이 불투명하면 결과도 불투명하게 만듭니다.
    static func fit(_ result: CGImage, to original: CGImage, keepTransparency: Bool) throws -> CGImage {
        var output = result
        let originalRatio = Double(original.width) / Double(original.height)
        let resultRatio = Double(result.width) / Double(result.height)
        if abs(originalRatio - resultRatio) / originalRatio < 0.02,
           result.width != original.width || result.height != original.height {
            output = try ImageOps.resize(output, width: original.width, height: original.height)
        }
        if !keepTransparency && !original.hasAlpha && output.hasAlpha {
            output = try ImageOps.flatten(output)
        }
        return output
    }
}
