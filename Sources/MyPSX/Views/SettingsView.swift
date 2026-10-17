import PSXCore
import SwiftUI

/// 설정 창 (⌘,): AI 연결 방식 (ChatGPT 구독의 Codex CLI / OpenAI API 키 / Higgsfield 구독의 CLI)
struct SettingsView: View {
    @EnvironmentObject private var settings: GPTSettings
    @State private var keyInput = ""
    @State private var status: Status?
    @State private var checking = false

    private enum Status {
        case success(String)
        case failure(String)
    }

    /// 예: "0.1.0 (d2a9bca)" — 어떤 빌드를 쓰고 있는지 확인할 때 봅니다.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "개발용"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty || build == short ? short : "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Picker("연결 방식", selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.provider) { _, _ in status = nil }
                Text("AI로 사진을 수정하거나 배경을 정리할 때 쓸 연결 방식입니다. 수정할 사진은 고른 서비스(OpenAI 또는 Higgsfield)로 전송됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI 연결")
            }

            switch settings.provider {
            case .codex: codexSection
            case .apiKey: apiKeySection
            case .higgsfield: higgsfieldSection
            }

            Section {
                HStack {
                    Button(checking ? "확인 중…" : "연결 확인") { check() }
                        .disabled(!settings.isReady || checking)
                    statusLabel
                }
                .font(.callout)
            }

            Section {
                Text("My PSX \(Self.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 600)
        .padding(.vertical, 8)
    }

    // MARK: Codex

    private var codexSection: some View {
        Section {
            Text("ChatGPT 구독(Plus 이상)으로 로그인한 Codex CLI가 사진을 수정합니다. API 키나 추가 요금이 필요 없습니다.")
            VStack(alignment: .leading, spacing: 6) {
                Text("처음 한 번만 터미널에서:").font(.caption.weight(.semibold))
                Text("1.  brew install codex     (또는 npm install -g @openai/codex)")
                Text("2.  codex login     → ChatGPT 계정으로 로그인")
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            Text("⚠️ 실험 기능입니다. OpenAI가 공식 지원하는 연동 방식이 아니라 Codex 업데이트에 따라 안 될 수 있고, 이미지를 새로 그리므로 수십 초 이상 걸리고, 구독의 Codex 사용량을 글보다 많이 씁니다.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("ChatGPT 구독 (Codex CLI)")
        }
    }

    // MARK: Higgsfield

    private var higgsfieldSection: some View {
        Section {
            Text("Higgsfield 구독으로 로그인한 Higgsfield CLI를 씁니다. API 키 없이 구독 크레딧을 씁니다. 배경 제거는 전용 모델(1장 ≈ 1크레딧)이라 빠르고 상품이 원본 그대로이며, 글로 하는 수정은 GPT Image 2.5를 씁니다.")
            VStack(alignment: .leading, spacing: 6) {
                Text("처음 한 번만 터미널에서:").font(.caption.weight(.semibold))
                Text("1.  brew install higgsfield-ai/tap/higgsfield     (또는 npm install -g @higgsfield/cli)")
                Text("2.  higgsfield auth login     → Higgsfield 계정으로 로그인")
                Text("3.  higgsfield workspace list     → 나온 ID로 higgsfield workspace set <ID>")
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            Text("Higgsfield 웹의 '무제한' 혜택은 CLI에는 적용되지 않아, 쓸 때마다 크레딧이 차감됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Higgsfield 구독 (CLI)")
        }
    }

    // MARK: API 키

    @ViewBuilder
    private var apiKeySection: some View {
        Section {
            Text("ChatGPT 구독과는 별도로, 사용한 만큼 OpenAI에 요금이 청구됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("API 키 발급받기 (platform.openai.com) ↗",
                 destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.caption)
            HStack {
                SecureField(text: $keyInput,
                            prompt: Text(settings.hasAPIKey ? "저장됨 — 바꾸려면 새 키 입력" : "sk-...")) {
                    Text("API 키")
                }
                .textFieldStyle(.roundedBorder)
                Button("저장") { save() }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Label(settings.hasAPIKey ? "API 키가 저장되어 있습니다 (키체인)" : "API 키가 없습니다",
                      systemImage: settings.hasAPIKey ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(settings.hasAPIKey ? .green : .secondary)
                Spacer()
                if settings.hasAPIKey {
                    Button("삭제", role: .destructive) {
                        settings.removeAPIKey()
                        status = nil
                    }
                }
            }
            .font(.callout)
        } header: {
            Text("OpenAI API 키")
        }

        Section {
            HStack {
                TextField(text: $settings.model, prompt: Text(OpenAIImageClient.defaultModel)) {
                    Text("모델")
                }
                .textFieldStyle(.roundedBorder)
                Menu("추천") {
                    ForEach(GPTSettings.suggestedModels, id: \.self) { name in
                        Button(name) { settings.model = name }
                    }
                }
                .fixedSize()
            }
            if settings.model.hasPrefix("gpt-image-2") {
                Text("이 모델은 투명 배경을 직접 만들지 못해, '투명 배경'을 켜면 흰 배경으로 정리한 뒤 macOS 기능으로 지웁니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("이미지 모델")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(3)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(4)
        case nil:
            EmptyView()
        }
    }

    private func save() {
        do {
            try settings.saveAPIKey(keyInput)
            keyInput = ""
            status = nil
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    private func check() {
        checking = true
        status = nil
        let provider = settings.provider
        let client = settings.makeClient()
        Task {
            do {
                switch provider {
                case .codex:
                    let text = try await CodexImageClient().loginStatus()
                    status = .success(text)
                case .apiKey:
                    guard let client else { throw GPTError.missingKey }
                    try await client.checkConnection()
                    status = .success("연결되었습니다 (\(client.model))")
                case .higgsfield:
                    let text = try await HiggsfieldClient().accountStatus()
                    status = .success(text)
                }
            } catch {
                status = .failure(error.localizedDescription)
            }
            checking = false
        }
    }
}
