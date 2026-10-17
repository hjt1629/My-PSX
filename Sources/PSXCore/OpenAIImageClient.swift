import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// OpenAI 이미지 편집 API(/v1/images/edits)로 사진을 수정합니다.
/// ChatGPT 구독과는 별개인 OpenAI API 키가 필요합니다. (사용한 만큼 과금)
public struct OpenAIImageClient: Sendable {
    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public var session: URLSession

    public static let defaultModel = "gpt-image-1.5"
    /// 업로드 전에 이 크기로 줄입니다. (결과도 최대 1536px)
    static let maxUploadPixelSize = 2048

    public init(apiKey: String, model: String = OpenAIImageClient.defaultModel,
                baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    /// 사진을 지시문대로 수정합니다.
    /// - Parameter transparentBackground: true면 배경을 투명하게 만든 PNG를 요청합니다.
    public func edit(_ image: CGImage, prompt: String, transparentBackground: Bool = false) async throws -> CGImage {
        let upload = try ImageOps.downscaled(image, maxPixelSize: Self.maxUploadPixelSize)
        var form = MultipartForm()
        form.addField("model", model)
        form.addField("prompt", prompt)
        form.addField("n", "1")
        form.addField("size", Self.requestSize(for: image.pixelSize))
        form.addField("output_format", "png")
        if transparentBackground {
            form.addField("background", "transparent")
        }
        form.addFile("image", filename: "image.png", contentType: "image/png",
                     data: try ImageEncoding.pngData(upload))

        var request = URLRequest(url: baseURL.appendingPathComponent("images/edits"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalizedBody

        let data = try await send(request)
        let result = try Self.decodeImage(from: data)
        return try Self.fitResult(result, to: image, keepTransparency: transparentBackground)
    }

    /// API 키와 모델 이름이 맞는지 확인합니다.
    public func checkConnection() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("models").appendingPathComponent(model))
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        guard !apiKey.isEmpty else { throw GPTError.missingKey }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GPTError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GPTError.from(status: http.statusCode, body: data)
        }
        return data
    }

    // MARK: 도우미

    /// 원본 비율에 가장 가까운 요청 크기
    static func requestSize(for size: CGSize) -> String {
        let ratio = size.height > 0 ? size.width / size.height : 1
        if ratio > 1.2 { return "1536x1024" }
        if ratio < 1 / 1.2 { return "1024x1536" }
        return "1024x1024"
    }

    static func decodeImage(from data: Data) throws -> CGImage {
        struct Response: Decodable {
            struct Item: Decodable { let b64_json: String? }
            let data: [Item]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let base64 = response.data.first?.b64_json,
              let imageData = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GPTError.invalidResponse
        }
        return image
    }

    /// 결과의 비율이 원본과 거의 같으면 원본 크기로 맞춥니다.
    /// 투명 배경을 요청하지 않았고 원본이 불투명하면 결과도 불투명하게 만듭니다.
    static func fitResult(_ result: CGImage, to original: CGImage, keepTransparency: Bool) throws -> CGImage {
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

public enum GPTError: LocalizedError, Equatable {
    case missingKey
    case unauthorized
    case api(status: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "OpenAI API 키가 없습니다. 설정(⌘,)에서 API 키를 넣어 주세요."
        case .unauthorized:
            return "OpenAI API 키가 올바르지 않습니다. 설정(⌘,)에서 키를 확인해 주세요."
        case .api(let status, let message):
            return "OpenAI 오류 (\(status)): \(message)"
        case .invalidResponse:
            return "OpenAI 응답을 이해하지 못했습니다."
        }
    }

    static func from(status: Int, body: Data) -> GPTError {
        if status == 401 { return .unauthorized }
        struct ErrorBody: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error.message
            ?? String(data: body, encoding: .utf8) ?? ""
        return .api(status: status, message: message)
    }
}

public enum ImageEncoding {
    public static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageError.writeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.writeFailed }
        return data as Data
    }
}

/// multipart/form-data 요청 본문
struct MultipartForm {
    let boundary = "PSXBoundary-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// 마지막 경계까지 붙인 완성된 본문
    var finalizedBody: Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}
