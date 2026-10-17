import PSXCore
import SwiftUI

/// 설정 창 (⌘,): OpenAI API 키와 모델
struct SettingsView: View {
    @EnvironmentObject private var settings: GPTSettings
    @State private var keyInput = ""
    @State private var status: Status?
    @State private var checking = false

    private enum Status {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                Text("GPT로 사진을 수정하거나 배경을 지우려면 OpenAI API 키가 필요합니다.")
                Text("ChatGPT 구독(Plus/Pro)과는 별도로, 사용한 만큼 OpenAI에 요금이 청구됩니다. 사진은 수정할 때 OpenAI 서버로 전송됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("API 키 발급받기 (platform.openai.com) ↗",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            } header: {
                Text("GPT 연동")
            }

            Section {
                HStack {
                    SecureField(settings.hasAPIKey ? "저장됨 — 바꾸려면 새 키 입력" : "sk-...", text: $keyInput)
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
                Text("API 키")
            }

            Section {
                HStack {
                    TextField("모델", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                    Menu("추천") {
                        ForEach(GPTSettings.suggestedModels, id: \.self) { name in
                            Button(name) { settings.model = name }
                        }
                    }
                    .fixedSize()
                }
                if !settings.supportsTransparency {
                    Text("⚠️ 이 모델은 투명 배경을 지원하지 않아 'GPT로 배경 제거'를 쓸 수 없습니다. 배경 제거에는 gpt-image-1.5를 권장합니다.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("이미지 모델")
            }

            Section {
                HStack {
                    Button(checking ? "확인 중…" : "연결 확인") { check() }
                        .disabled(!settings.hasAPIKey || checking)
                    switch status {
                    case .success(let message):
                        Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    case nil:
                        EmptyView()
                    }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
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
        guard let client = settings.makeClient() else { return }
        checking = true
        status = nil
        Task {
            do {
                try await client.checkConnection()
                status = .success("연결되었습니다 (\(client.model))")
            } catch {
                status = .failure(error.localizedDescription)
            }
            checking = false
        }
    }
}
