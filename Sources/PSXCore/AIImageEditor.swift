import CoreGraphics
import Foundation

/// 글로 사진을 수정해 주는 AI (OpenAI API 키 방식 / ChatGPT 구독의 Codex CLI 방식)
public protocol AIImageEditor: Sendable {
    /// 화면에 보여줄 이름
    var displayName: String { get }
    /// 투명 배경 결과를 직접 만들 수 있는지
    var supportsTransparentBackground: Bool { get }
    /// - Parameter transparentBackground: true면 투명 배경 PNG를 요청합니다. (지원할 때만)
    func edit(_ image: CGImage, prompt: String, transparentBackground: Bool) async throws -> CGImage
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
