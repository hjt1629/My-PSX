import CoreGraphics

extension CGImage {
    /// 알파 채널(투명도)을 가진 이미지인지 여부
    public var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    public var pixelSize: CGSize { CGSize(width: width, height: height) }
}
