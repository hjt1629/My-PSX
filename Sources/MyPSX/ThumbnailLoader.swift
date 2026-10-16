import CoreGraphics
import Foundation
import PSXCore

/// 썸네일을 백그라운드에서 만들고 메모리에 캐시합니다.
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    /// 썸네일 슬라이더를 움직여도 다시 만들지 않도록 넉넉한 크기로 한 번만 만듭니다.
    static let pixelSize = 640

    private let cache = NSCache<NSURL, CGImage>()

    private init() {
        cache.countLimit = 2000
    }

    func cachedThumbnail(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)
    }

    func thumbnail(for url: URL) async -> CGImage? {
        if let cached = cachedThumbnail(for: url) { return cached }
        let image = await Task.detached(priority: .utility) {
            ImageLoader.thumbnail(for: url, maxPixelSize: Self.pixelSize)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    func invalidate(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
