import Foundation

public enum ImageError: LocalizedError {
    case cannotOpen
    case renderFailed
    case noForeground
    case unsupportedFormat
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .cannotOpen: return "이미지를 열 수 없습니다."
        case .renderFailed: return "이미지를 처리하지 못했습니다."
        case .noForeground: return "사진에서 피사체를 찾지 못했습니다."
        case .unsupportedFormat: return "지원하지 않는 파일 형식입니다."
        case .writeFailed: return "파일을 저장하지 못했습니다."
        }
    }
}
