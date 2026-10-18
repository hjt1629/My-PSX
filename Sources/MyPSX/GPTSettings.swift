import Foundation
import PSXCore
import Security

/// GPT를 어떤 방식으로 쓸지
enum AIProvider: String, CaseIterable, Identifiable {
    /// ChatGPT 구독 (맥에 설치된 Codex CLI에 로그인)
    case codex
    /// OpenAI API 키 (사용량만큼 별도 과금)
    case apiKey
    /// Higgsfield 구독 (맥에 설치된 Higgsfield CLI에 로그인, 구독 크레딧 사용)
    case higgsfield

    var id: Self { self }

    var title: String {
        switch self {
        case .codex: return "ChatGPT 구독 (Codex CLI) — 실험 기능"
        case .apiKey: return "OpenAI API 키"
        case .higgsfield: return "Higgsfield 구독 (CLI)"
        }
    }
}

/// GPT 연동 설정. API 키는 macOS 키체인에 안전하게 저장합니다.
@MainActor
final class GPTSettings: ObservableObject {
    @Published private(set) var hasAPIKey = false
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: modelKey) }
    }
    @Published var provider: AIProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: providerKey) }
    }

    /// 자주 쓰는 모델. gpt-image-2는 투명 배경을 지원하지 않습니다.
    static let suggestedModels = ["gpt-image-1.5", "gpt-image-1", "gpt-image-1-mini", "gpt-image-2"]

    private let modelKey = "openAIImageModel"
    private let providerKey = "aiProvider"
    private let keychainService = "com.hjt1629.mypsx.openai"
    private let keychainAccount = "api-key"

    init() {
        model = UserDefaults.standard.string(forKey: modelKey) ?? OpenAIImageClient.defaultModel
        provider = UserDefaults.standard.string(forKey: "aiProvider").flatMap(AIProvider.init(rawValue:)) ?? .codex
        hasAPIKey = !(apiKey ?? "").isEmpty
    }

    /// 키체인에 저장된 키. 없으면 환경 변수 OPENAI_API_KEY (개발용)
    private var apiKey: String? {
        Keychain.read(service: keychainService, account: keychainAccount)
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try Keychain.save(trimmed, service: keychainService, account: keychainAccount)
        hasAPIKey = !trimmed.isEmpty
    }

    func removeAPIKey() {
        Keychain.delete(service: keychainService, account: keychainAccount)
        hasAPIKey = !(apiKey ?? "").isEmpty
    }

    /// 지금 고른 방식으로 쓸 수 있는지 (CLI 방식은 실행해 봐야 알 수 있어 항상 true)
    var isReady: Bool {
        provider != .apiKey || hasAPIKey
    }

    /// 지금 고른 방식의 AI 편집기
    func makeEditor() -> (any AIImageEditor)? {
        switch provider {
        case .codex: return CodexImageClient()
        case .apiKey: return makeClient()
        case .higgsfield: return HiggsfieldClient()
        }
    }

    /// API 키가 있으면 클라이언트를 만들어 줍니다.
    func makeClient() -> OpenAIImageClient? {
        guard let key = apiKey, !key.isEmpty else { return nil }
        let name = model.trimmingCharacters(in: .whitespaces)
        return OpenAIImageClient(apiKey: key, model: name.isEmpty ? OpenAIImageClient.defaultModel : name)
    }

    var providerName: String {
        makeEditor()?.displayName ?? provider.title
    }
}

/// 키체인 일반 암호 항목 읽기 / 쓰기
enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, service: String, account: String) throws {
        delete(service: service, account: account)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrLabel: "My PSX OpenAI API 키",
            kSecValueData: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "키체인에 저장하지 못했습니다. (\(status))"])
        }
    }

    static func delete(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
