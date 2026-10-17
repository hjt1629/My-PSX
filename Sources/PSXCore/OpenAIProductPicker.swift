import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// OpenAI API(Responses)로 번호 표시 사진을 보여 주고 상품 번호만 받습니다. 이미지 생성이 아니라 몇 초면 끝납니다.
public struct OpenAIProductPicker: AIProductPicker {
    public static let defaultModel = "gpt-5-mini"

    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public var session: URLSession

    public init(apiKey: String, model: String = OpenAIProductPicker.defaultModel,
                baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    public func pickProduct(in overlay: CGImage, labels: [Int]) async throws -> [Int] {
        guard !apiKey.isEmpty else { throw GPTError.missingKey }
        let imageURL = "data:image/jpeg;base64," + (try ImageEncoding.jpegData(overlay)).base64EncodedString()
        // 추론 모델은 생각을 짧게 할수록 빠릅니다. 모델마다 받는 값이 달라 차례로 시도합니다.
        var lastError: Error = GPTError.invalidResponse
        for effort in Self.reasoningEfforts(for: model) {
            do {
                let data = try await send(body(prompt: ProductPickPrompt.text(labels: labels),
                                               imageURL: imageURL, effort: effort))
                return ProductPickPrompt.parseLabels(try Self.outputText(from: data), valid: labels)
            } catch GPTError.api(let status, let message) where status == 400 && Self.isReasoningError(message) {
                lastError = GPTError.api(status: status, message: message)
                continue
            }
        }
        throw lastError
    }

    static func reasoningEfforts(for model: String) -> [String?] {
        let name = model.lowercased()
        let reasons = name.hasPrefix("gpt-5") || name.hasPrefix("o")
        return reasons ? ["minimal", "none", "low", nil] : [nil]
    }

    static func isReasoningError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("reasoning") || lower.contains("effort")
    }

    func body(prompt: String, imageURL: String, effort: String?) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "input": [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": prompt],
                    ["type": "input_image", "image_url": imageURL, "detail": "low"]
                ]
            ]],
            "max_output_tokens": 2000
        ]
        if let effort { body["reasoning"] = ["effort": effort] }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func send(_ body: Data) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GPTError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GPTError.from(status: http.statusCode, body: data)
        }
        return data
    }

    /// Responses 응답에서 답변 글을 모읍니다. (output[].content[] 중 type이 output_text인 것)
    static func outputText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GPTError.invalidResponse
        }
        if let text = object["output_text"] as? String { return text }
        var texts: [String] = []
        for item in object["output"] as? [[String: Any]] ?? [] {
            for part in item["content"] as? [[String: Any]] ?? [] where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String { texts.append(text) }
            }
        }
        guard !texts.isEmpty else { throw GPTError.invalidResponse }
        return texts.joined(separator: "\n")
    }
}

extension ImageEncoding {
    public static func jpegData(_ image: CGImage, quality: Double = 0.85) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageError.writeFailed
        }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.writeFailed }
        return data as Data
    }
}
