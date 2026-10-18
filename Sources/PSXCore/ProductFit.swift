import CoreGraphics
import Foundation

extension ImageOps {
    /// 상품이 있는 영역 (왼쪽 위 원점, 픽셀). 투명한 곳과 거의 흰색인 곳은 배경으로 봅니다. 상품이 없으면 nil.
    public static func contentBounds(_ image: CGImage, whiteThreshold: UInt8 = 245) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width {
                let i = row + x * 4
                let alpha = pixels[i + 3]
                guard alpha > 10 else { continue }
                // premultiplied: 흰색이면 각 값이 alpha와 거의 같습니다.
                let limit = Int(alpha) * Int(whiteThreshold) / 255
                if Int(pixels[i]) >= limit && Int(pixels[i + 1]) >= limit && Int(pixels[i + 2]) >= limit && alpha > 250 {
                    continue
                }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // CGContext의 첫 줄이 이미지의 위쪽이라 y는 그대로 왼쪽 위 원점입니다.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// 쇼핑몰 규격: 상품을 잘라 내 size×size 캔버스 가운데에 여백(margin, 0~0.4)을 두고 놓습니다.
    /// transparent면 배경을 투명하게, 아니면 흰색으로 채웁니다.
    public static func fitToSquare(_ image: CGImage, size: Int, margin: Double, transparent: Bool) throws -> CGImage {
        let canvas = max(16, size)
        let bounds = contentBounds(image) ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let product = try crop(image, to: bounds)

        let available = Double(canvas) * (1 - 2 * min(max(margin, 0), 0.4))
        let scale = available / Double(max(product.width, product.height))
        let width = max(1, Int((Double(product.width) * scale).rounded()))
        let height = max(1, Int((Double(product.height) * scale).rounded()))

        let context = try makeContext(width: canvas, height: canvas, like: image, alpha: transparent)
        let rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        if !transparent {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
        }
        context.interpolationQuality = .high
        context.draw(product, in: CGRect(x: (canvas - width) / 2, y: (canvas - height) / 2, width: width, height: height))
        return try makeImage(context)
    }
}

extension ImageOps {
    /// image를 width×height 캔버스의 rect(왼쪽 위 원점, 픽셀) 위치에 그립니다. 캔버스 밖으로 나간 부분은 잘립니다.
    /// background가 nil이면 투명 배경입니다.
    public static func place(_ image: CGImage, canvasWidth width: Int, height: Int, at rect: CGRect,
                             background: CGColor? = CGColor(gray: 1, alpha: 1)) throws -> CGImage {
        let width = max(1, width), height = max(1, height)
        let context = try makeContext(width: width, height: height, like: image, alpha: background == nil)
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.interpolationQuality = .high
        // CGContext는 왼쪽 아래 원점
        context.draw(image, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY,
                                       width: rect.width, height: rect.height))
        return try makeImage(context)
    }
}
