import AppKit
import PSXCore
import SwiftUI

// MARK: - 사진 편집 탭의 오른쪽 패널

/// 오른쪽 패널 위쪽 아이콘 탭
enum EditPanelTab: String, CaseIterable, Identifiable {
    case tools, adjust, ai

    var id: Self { self }

    var title: String {
        switch self {
        case .tools: return "편집"
        case .adjust: return "조정"
        case .ai: return "AI"
        }
    }

    var systemImage: String {
        switch self {
        case .tools: return "square.and.pencil"
        case .adjust: return "slider.horizontal.3"
        case .ai: return "sparkles"
        }
    }
}

struct EditPanel: View {
    @ObservedObject var editor: PhotoEditor
    @Binding var cropAspect: CropAspect
    @Binding var tool: EditTool?
    let onRemoveBackground: () -> Void
    @State private var panelTab: EditPanelTab = .tools

    var body: some View {
        if editor.mode == .crop {
            CropPanel(editor: editor, cropAspect: $cropAspect)
        } else if tool == .resize, let image = editor.image {
            ResizePanel(originalSize: image.pixelSize) { width, height in
                editor.resize(width: width, height: height)
                tool = nil
            } onCancel: {
                tool = nil
            }
        } else {
            VStack(spacing: 0) {
                PanelTabs(selection: $panelTab)
                    .disabled(editor.isBusy)
                PanelDivider(vertical: false)
                switch panelTab {
                case .tools: toolList
                case .adjust: AdjustPanel(editor: editor)
                case .ai: AIEditPanel(editor: editor)
                }
            }
        }
    }

    private var toolList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 회전 / 반전
                HStack(spacing: 4) {
                    IconToolButton(systemImage: "rotate.left", help: "왼쪽으로 90° 회전 (⌘[)") {
                        editor.rotate(clockwise: false)
                    }
                    IconToolButton(systemImage: "rotate.right", help: "오른쪽으로 90° 회전 (⌘])") {
                        editor.rotate(clockwise: true)
                    }
                    IconToolButton(systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                                   help: "좌우 반전") {
                        editor.flip(horizontal: true)
                    }
                    IconToolButton(systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                                   help: "상하 반전") {
                        editor.flip(horizontal: false)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

                // 도구 (2열)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)],
                          spacing: 4) {
                    ToolRow(title: "크기 조절", systemImage: "arrow.up.left.and.arrow.down.right",
                            help: "크기 조절 (⌥⌘I)") {
                        tool = .resize
                    }
                    ToolRow(title: "자르기", systemImage: "crop", help: "자르기 (⌘K)") {
                        guard let image = editor.image else { return }
                        editor.beginCrop(aspect: cropAspect.ratio(for: image.pixelSize))
                    }
                    ToolRow(title: "오려내기", systemImage: "scissors", help: "배경 제거 (⇧⌘B)") {
                        onRemoveBackground()
                    }
                }
                .padding(.horizontal, 6)
            }
            .padding(.bottom, 12)
        }
        .disabled(!editor.canEdit)
    }
}

/// PhotoScape X처럼 아이콘 + 이름으로 된 패널 탭
private struct PanelTabs: View {
    @Binding var selection: EditPanelTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditPanelTab.allCases) { tab in
                PanelTabButton(tab: tab, selected: selection == tab) { selection = tab }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

private struct PanelTabButton: View {
    let tab: EditPanelTab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let color: Color = selected ? Theme.accent : Theme.secondaryText
        return Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17))
                Text(tab.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(color)
            .frame(width: 54, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(DarkButtonStyle())
        .help(tab.title)
    }
}

/// 회전 줄의 아이콘 버튼
private struct IconToolButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(DarkButtonStyle())
        .help(help)
    }
}

/// 아이콘 + 이름 도구 버튼 (2열 격자에 들어감)
private struct ToolRow: View {
    let title: String
    let systemImage: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(DarkButtonStyle())
        .help(help ?? title)
    }
}

/// 패널 아래쪽의 취소 / 적용 버튼
private struct PanelActions: View {
    let applyTitle: String
    var applyDisabled = false
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Text("취소")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
            }
            .buttonStyle(DarkButtonStyle())

            Button(action: onApply) {
                Text(applyTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(DarkButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(applyDisabled)
        }
        .font(.system(size: 12))
        .padding(12)
    }
}

// MARK: - 자르기

private struct CropPanel: View {
    @EnvironmentObject private var browser: FolderBrowser
    @ObservedObject var editor: PhotoEditor
    @Binding var cropAspect: CropAspect
    @State private var copied = false

    /// 선택 영역을 새 파일로 저장. 기본 위치는 사진이 있는 폴더입니다.
    private func saveSelection() {
        guard let image = editor.image else { return }
        let source = editor.sourceURL
        let original = source.pathExtension.lowercased()
        let fileExtension = image.hasAlpha ? "png"
            : (ImageExporter.canWrite(fileExtension: original) ? original : "jpg")
        let panel = NSSavePanel()
        panel.directoryURL = source.deletingLastPathComponent()
        panel.nameFieldStringValue = "\(source.deletingPathExtension().lastPathComponent)_선택.\(fileExtension)"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "선택한 영역만 새 파일로 저장합니다. 편집 중인 사진은 그대로입니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if await editor.saveSelection(to: url) {
                ThumbnailLoader.shared.invalidate(url)
                browser.reload()
            }
        }
    }

    private func flashCopied() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "자르기")
            Text("사진 위에서 드래그해 영역을 고르세요. 모서리를 끌면 크기가, 안쪽을 끌면 위치가 바뀝니다.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            PanelHeader(title: "비율")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(CropAspect.allCases) { aspect in
                    Button {
                        cropAspect = aspect
                        if let image = editor.image {
                            editor.resetCropRect(aspect: aspect.ratio(for: image.pixelSize))
                        }
                    } label: {
                        Text(aspect.title)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                    }
                    .buttonStyle(DarkButtonStyle(selected: cropAspect == aspect))
                }
            }
            .padding(.horizontal, 12)

            PanelHeader(title: "선택 영역")
            Text("\(Int(editor.cropRect.width.rounded())) × \(Int(editor.cropRect.height.rounded())) px")
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            // 사진은 그대로 두고 선택 영역만 내보내기
            VStack(spacing: 6) {
                Button(action: saveSelection) {
                    Label("선택 영역 저장… (⌘A)", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                }
                .buttonStyle(DarkButtonStyle())
                .keyboardShortcut("a", modifiers: .command)

                Button {
                    if editor.copySelectionToClipboard() { flashCopied() }
                } label: {
                    Label(copied ? "복사했습니다" : "클립보드에 복사 (⌘B)",
                          systemImage: copied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                }
                .buttonStyle(DarkButtonStyle())
                .keyboardShortcut("b", modifiers: .command)
            }
            .disabled(editor.cropRect.width < 1 || editor.cropRect.height < 1)
            .padding(.horizontal, 12)

            Spacer()
            PanelActions(applyTitle: "자르기 적용",
                         applyDisabled: editor.cropRect.width < 1 || editor.cropRect.height < 1,
                         onCancel: { editor.cancelCrop() },
                         onApply: { editor.applyCrop() })
        }
    }
}

// MARK: - 크기 조절

private struct ResizePanel: View {
    let originalSize: CGSize
    let onApply: (Int, Int) -> Void
    let onCancel: () -> Void

    private enum Field { case width, height }

    @State private var width: Int
    @State private var height: Int
    @State private var widthText: String
    @State private var heightText: String
    @State private var keepAspect = true
    @FocusState private var focused: Field?

    private let maxDimension = 20_000

    init(originalSize: CGSize, onApply: @escaping (Int, Int) -> Void, onCancel: @escaping () -> Void) {
        self.originalSize = originalSize
        self.onApply = onApply
        self.onCancel = onCancel
        let w = Int(originalSize.width), h = Int(originalSize.height)
        _width = State(initialValue: w)
        _height = State(initialValue: h)
        _widthText = State(initialValue: String(w))
        _heightText = State(initialValue: String(h))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "크기 조절")
            Text("원본  \(Int(originalSize.width)) × \(Int(originalSize.height)) px")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("너비")
                    TextField("", text: textBinding(.width))
                        .focused($focused, equals: .width)
                        .frame(width: 110)
                    Text("px").foregroundStyle(Theme.secondaryText)
                }
                GridRow {
                    Text("높이")
                    TextField("", text: textBinding(.height))
                        .focused($focused, equals: .height)
                        .frame(width: 110)
                    Text("px").foregroundStyle(Theme.secondaryText)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)

            Toggle("가로세로 비율 유지", isOn: $keepAspect)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            PanelHeader(title: "빠른 선택")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach([25, 50, 75, 200], id: \.self) { percent in
                    Button {
                        applyPercent(percent)
                    } label: {
                        Text("\(percent)%")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                    }
                    .buttonStyle(DarkButtonStyle())
                }
            }
            .padding(.horizontal, 12)

            Spacer()
            PanelActions(applyTitle: "적용",
                         applyDisabled: width == Int(originalSize.width) && height == Int(originalSize.height),
                         onCancel: onCancel,
                         onApply: { onApply(width, height) })
        }
        .onAppear { focused = .width }
    }

    private var ratio: Double {
        originalSize.height > 0 ? originalSize.width / originalSize.height : 1
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, 1), maxDimension)
    }

    /// 글자를 칠 때마다 바로 숫자에 반영합니다. (비율 유지 중이면 반대쪽도 함께 바뀜)
    private func textBinding(_ field: Field) -> Binding<String> {
        Binding(
            get: { field == .width ? widthText : heightText },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(5))
                if field == .width { widthText = digits } else { heightText = digits }
                guard let value = Int(digits), value > 0 else { return }
                if field == .width {
                    width = clamp(value)
                    if keepAspect {
                        height = clamp(Int((Double(width) / ratio).rounded()))
                        heightText = String(height)
                    }
                } else {
                    height = clamp(value)
                    if keepAspect {
                        width = clamp(Int((Double(height) * ratio).rounded()))
                        widthText = String(width)
                    }
                }
            }
        )
    }

    private func applyPercent(_ percent: Int) {
        width = clamp(Int((originalSize.width * Double(percent) / 100).rounded()))
        height = clamp(Int((originalSize.height * Double(percent) / 100).rounded()))
        widthText = String(width)
        heightText = String(height)
    }
}

// MARK: - 조정 (밝기 / 대비 / 채도)

private struct AdjustPanel: View {
    @ObservedObject var editor: PhotoEditor
    @State private var adjustments = ImageAdjustments()

    private static let warmCool = [Color(red: 0.25, green: 0.5, blue: 1), Color(white: 0.75), Color(red: 1, green: 0.8, blue: 0.2)]
    private static let greenMagenta = [Color(red: 0.2, green: 0.8, blue: 0.3), Color(white: 0.75), Color(red: 0.9, green: 0.3, blue: 0.8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AdjustSection(title: "흰색 균형", key: "wb", isChanged: changed(\.temperature, \.tint),
                                  onReset: { reset(\.temperature, \.tint) }) {
                        AdjustSlider(title: "색온도", value: $adjustments.temperature, track: Self.warmCool)
                        AdjustSlider(title: "색조", value: $adjustments.tint, track: Self.greenMagenta)
                    }
                    AdjustSection(title: "톤", key: "tone",
                                  isChanged: changed(\.exposure, \.brightness, \.contrast, \.highlights,
                                                     \.shadows, \.whites, \.blacks),
                                  onReset: { reset(\.exposure, \.brightness, \.contrast, \.highlights,
                                                   \.shadows, \.whites, \.blacks) }) {
                        AdjustSlider(title: "노출", value: $adjustments.exposure,
                                     format: { String(format: "%+.2f", $0 / 50) })
                        AdjustSlider(title: "밝기", value: $adjustments.brightness)
                        AdjustSlider(title: "대비", value: $adjustments.contrast)
                        AdjustSlider(title: "밝은 영역", value: $adjustments.highlights)
                        AdjustSlider(title: "어두운 영역", value: $adjustments.shadows)
                        AdjustSlider(title: "흰색 계열", value: $adjustments.whites)
                        AdjustSlider(title: "검정 계열", value: $adjustments.blacks)
                    }
                    AdjustSection(title: "외관", key: "presence",
                                  isChanged: changed(\.clarity, \.vibrance, \.saturation),
                                  onReset: { reset(\.clarity, \.vibrance, \.saturation) }) {
                        AdjustSlider(title: "부분 대비", value: $adjustments.clarity)
                        AdjustSlider(title: "생동감", value: $adjustments.vibrance)
                        AdjustSlider(title: "채도", value: $adjustments.saturation)
                    }
                    AdjustSection(title: "세부 · 효과", key: "detail",
                                  isChanged: changed(\.sharpness, \.vignette),
                                  onReset: { reset(\.sharpness, \.vignette) }) {
                        AdjustSlider(title: "선명하게", value: $adjustments.sharpness, range: 0...100)
                        AdjustSlider(title: "비네팅", value: $adjustments.vignette)
                    }

                    Text("슬라이더 이름을 더블클릭하면 0으로 돌아갑니다. 움직이면 바로 미리 보이고, '적용'을 누르면 원본 크기로 반영됩니다.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            PanelDivider(vertical: false)
            PanelActions(applyTitle: "적용",
                         applyDisabled: adjustments.isIdentity || editor.isBusy,
                         onCancel: { adjustments = ImageAdjustments() },
                         onApply: {
                             editor.applyAdjustments(adjustments)
                             adjustments = ImageAdjustments()
                         })
        }
        .disabled(editor.image == nil || editor.isBusy)
        .onChange(of: adjustments) { _, newValue in
            editor.updateAdjustmentPreview(newValue)
        }
        .onDisappear { editor.endAdjustmentPreview() }
    }

    private func changed(_ keys: WritableKeyPath<ImageAdjustments, Double>...) -> Bool {
        keys.contains { adjustments[keyPath: $0] != 0 }
    }

    private func reset(_ keys: WritableKeyPath<ImageAdjustments, Double>...) {
        for key in keys { adjustments[keyPath: key] = 0 }
    }
}

/// 라이트룸처럼 접고 펼 수 있는 조정 묶음
private struct AdjustSection<Content: View>: View {
    let title: String
    let isChanged: Bool
    let onReset: () -> Void
    let content: Content
    @AppStorage private var collapsed: Bool

    init(title: String, key: String, isChanged: Bool, onReset: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.isChanged = isChanged
        self.onReset = onReset
        self.content = content()
        _collapsed = AppStorage(wrappedValue: false, "adjustCollapsed.\(key)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if isChanged {
                    Button("초기화", action: onReset)
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { collapsed.toggle() } }

            if !collapsed {
                content
                    .padding(.bottom, 6)
            }
            PanelDivider(vertical: false)
        }
    }
}

private struct AdjustSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -100...100
    /// 슬라이더 아래 색 막대 (색온도·색조)
    var track: [Color]? = nil
    var format: (Double) -> String = { $0 > 0 ? "+\(Int($0))" : "\(Int($0))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text)
                    .onTapGesture(count: 2) { value = 0 }
                    .help("더블클릭하면 0으로")
                Spacer()
                Text(format(value))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(value == 0 ? Theme.secondaryText : Theme.accent)
                    .onTapGesture(count: 2) { value = 0 }
            }
            // step을 주면 macOS가 눈금 200여 개를 그려 느려지므로, 값만 정수로 맞춥니다.
            Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range)
                .controlSize(.mini)
            if let track {
                LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
                    .clipShape(Capsule())
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}

// MARK: - AI (GPT로 수정)

private struct AIEditPanel: View {
    @EnvironmentObject private var gpt: GPTSettings
    @EnvironmentObject private var jobs: BackgroundJobs
    var cutout = CutoutSettings()
    @ObservedObject var editor: PhotoEditor
    @State private var prompt = ""
    @AppStorage("cutoutTransparent") private var transparent = false

    private let examples = [
        "상품만 남기고 배경을 연회색으로 바꿔줘",
        "조명을 밝고 자연스럽게 보정해줘",
        "제품 사진처럼 그림자를 부드럽게 넣어줘",
        "사진 속 먼지와 잡티를 지워줘"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "GPT로 수정")
                if gpt.isReady {
                    promptEditor
                } else {
                    setup
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("원하는 수정을 글로 쓰면 GPT가 사진을 고쳐 줍니다. 설정에서 OpenAI API 키를 넣거나, 연결 방식을 'ChatGPT 구독 (Codex CLI)'로 바꿔 주세요.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("API 키 방식은 ChatGPT 구독과 별도로 사용한 만큼 요금이 나갑니다.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLink {
                Label("설정 열기…", systemImage: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(DarkButtonStyle(prominent: true))
        }
        .padding(.horizontal, 14)
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 기본 기능: 글을 쓰지 않고 한 번에 상품만 남기기
            Button {
                guard let ai = gpt.makeEditor(), let image = editor.image else { return }
                jobs.removeBackground(source: editor.sourceURL, image: image, ai: ai, options: cutout.options)
            } label: {
                VStack(spacing: 2) {
                    Label("빠른 배경 제거 (상품만 남기기)", systemImage: "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(transparent ? "상품 외 전부 투명하게" : "상품 외 배경·아이콘·글자를 모두 흰색으로")
                        .font(.system(size: 10))
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(DarkButtonStyle(prominent: true))
            .disabled(!editor.canEdit || jobs.isRunning(editor.sourceURL))
            .help("⇧⌘B · 끝나면 같은 폴더에 '원래이름-1'로 저장합니다. 투명/흰색은 오려내기 탭의 '투명 배경으로' 체크박스를 따릅니다")

            Text("직접 지시하기")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 96)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)))
                if prompt.isEmpty {
                    Text("예: 배경을 하얀 대리석으로 바꿔줘")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        prompt = example
                    } label: {
                        Text(example)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(DarkButtonStyle())
                }
            }

            Button {
                guard let ai = gpt.makeEditor() else { return }
                editor.aiEdit(ai, prompt: prompt)
            } label: {
                Label("GPT로 수정하기", systemImage: "wand.and.rays")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
            }
            .buttonStyle(DarkButtonStyle())
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editor.canEdit)

            Text(footnote)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
    }

    private var footnote: String {
        switch gpt.provider {
        case .codex:
            return "연결: ChatGPT 구독 (Codex CLI) · 구독의 Codex 사용량을 씁니다. 사진이 OpenAI로 전송됩니다. 결과는 '되돌리기'로 취소할 수 있습니다."
        case .apiKey:
            return "연결: OpenAI API (\(gpt.model)) · 사용량만큼 요금이 나가고 사진이 OpenAI로 전송됩니다. 결과는 '되돌리기'로 취소할 수 있습니다."
        case .higgsfield:
            return "연결: Higgsfield 구독 (CLI, GPT Image 2.5) · 구독 크레딧을 씁니다. 사진이 Higgsfield로 전송됩니다. 결과는 '되돌리기'로 취소할 수 있습니다."
        }
    }
}

// MARK: - 쇼핑몰 규격 (정사각형 + 여백) / 저장 형식

private struct ShopFitOptions: View {
    @ObservedObject var editor: PhotoEditor
    @AppStorage("shopFitEnabled") private var enabled = false
    @AppStorage("shopFitSize") private var size = 1000
    @AppStorage("shopFitMargin") private var margin = 0.1
    @AppStorage("cutoutFormat") private var format: CutoutOptions.Format = .original
    @AppStorage("cutoutTransparent") private var transparent = false

    private let sizes = [800, 1000, 1200, 1500, 2000]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("정사각형 가운데 맞춤")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text("배경 제거 결과를 상품 크기에 맞춰 가운데 놓고 여백을 둡니다")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                Text("크기").font(.system(size: 11)).foregroundStyle(Theme.text)
                Picker("크기", selection: $size) {
                    ForEach(sizes, id: \.self) { Text("\($0) × \($0)").tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("여백").font(.system(size: 11)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Int((margin * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Slider(value: Binding(get: { margin }, set: { margin = ($0 * 100).rounded() / 100 }), in: 0...0.3)
                    .controlSize(.mini)
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)

            Button {
                editor.fitToSquare(size: size, margin: margin, transparent: transparent)
            } label: {
                Label("지금 사진에 바로 적용", systemImage: "square.dashed")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
            }
            .buttonStyle(DarkButtonStyle())
            .disabled(!editor.canEdit)
            .help("편집 중인 사진을 지금 설정(크기·여백)으로 맞춥니다. 되돌리기 가능")

            HStack(spacing: 6) {
                Text("저장 형식").font(.system(size: 11)).foregroundStyle(Theme.text)
                Picker("저장 형식", selection: $format) {
                    ForEach(CutoutOptions.Format.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            Text("JPG는 품질 92로 저장합니다. 투명 배경은 항상 PNG.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - 오려내기 탭의 오른쪽 패널

struct CutOutPanel: View {
    @EnvironmentObject private var gpt: GPTSettings
    @EnvironmentObject private var jobs: BackgroundJobs
    var cutout = CutoutSettings()
    @ObservedObject var editor: PhotoEditor
    let saveAsPNG: () -> Void

    @State private var customColor = Color(red: 0.2, green: 0.5, blue: 0.9)
    /// 꺼져 있으면 흰색 배경, 켜면 투명 배경
    @AppStorage("cutoutTransparent") private var transparent = false
    @AppStorage("cutoutLargestOnly") private var largestOnly = true
    /// 배경 제거 뒤 선명하게 (0~100, 기본 30)
    @AppStorage("cutoutSharpen") private var sharpen = 30.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "오려내기 (배경 제거)")
                Text("상품만 남기고 배경·아이콘·글자·소품을 모두 흰색으로 바꿉니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)

                Toggle(isOn: $transparent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("투명 배경으로")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text(transparent ? "배경을 투명하게 지웁니다 (PNG로 저장)" : "끄면 흰색 배경으로 만듭니다")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("끝난 뒤 선명하게")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(sharpen == 0 ? "끔" : "\(Int(sharpen))%")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(sharpen == 0 ? Theme.secondaryText : Theme.accent)
                    }
                    Slider(value: Binding(get: { sharpen }, set: { sharpen = ($0 / 5).rounded() * 5 }), in: 0...100)
                        .controlSize(.mini)
                    Text("AI가 아니라 맥에서 처리해 상품 모양은 바뀌지 않습니다")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

                // 기본: GPT(Codex 또는 API)가 상품만 남기고 나머지를 흰색/투명으로 — 맥 AI는 쓰지 않음
                Button {
                    guard let ai = gpt.makeEditor(), let image = editor.image else { return }
                    jobs.removeBackground(source: editor.sourceURL, image: image, ai: ai, options: cutout.options)
                } label: {
                    VStack(spacing: 2) {
                        Label("빠른 배경 제거", systemImage: "bolt.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(jobs.isRunning(editor.sourceURL)
                             ? "이 사진 처리 중… 다른 사진을 골라 계속 작업하세요"
                             : "끝나면 같은 폴더에 '\(editor.sourceURL.deletingPathExtension().lastPathComponent)-1'로 저장")
                            .font(.system(size: 10))
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(DarkButtonStyle(prominent: true))
                .disabled(!editor.canEdit || !gpt.isReady || jobs.isRunning(editor.sourceURL))
                .padding(.horizontal, 12)
                .help("⇧⌘B · 사진이 OpenAI로 전송됩니다.")

                Text(gptNote)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                PanelHeader(title: "쇼핑몰 규격으로 마무리")
                ShopFitOptions(editor: editor)

                PanelHeader(title: "인터넷 없이")
                Button {
                    editor.removeBackground(transparent: transparent, largestOnly: largestOnly)
                } label: {
                    Label("맥 AI로 제거 (무료 · 1초)", systemImage: "wand.and.stars")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(!editor.canEdit)
                .padding(.horizontal, 12)
                .help("⌥⌘B · macOS 내장 기능. 테두리가 거칠 수 있습니다.")

                Toggle(isOn: $largestOnly) {
                    Text("가장 큰 물체만 남기기")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text)
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 4)

                PanelHeader(title: "배경 채우기")
                Text(editor.hasTransparency
                     ? "투명한 부분을 원하는 색으로 채웁니다."
                     : "배경을 제거한 뒤에 사용할 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)

                HStack(spacing: 8) {
                    swatch("흰색", color: .white, cgColor: CGColor(gray: 1, alpha: 1))
                    swatch("검정", color: .black, cgColor: CGColor(gray: 0, alpha: 1))
                    swatch("회색", color: Color(white: 0.5), cgColor: CGColor(gray: 0.5, alpha: 1))
                }
                .padding(.horizontal, 12)

                HStack(spacing: 8) {
                    ColorPicker("다른 색", selection: $customColor, supportsOpacity: false)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button {
                        if let cgColor = NSColor(customColor).usingColorSpace(.sRGB)?.cgColor {
                            editor.fillBackground(cgColor)
                        }
                    } label: {
                        Text("채우기")
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                    }
                    .buttonStyle(DarkButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .disabled(!editor.hasTransparency || !editor.canEdit)

                PanelHeader(title: "저장")
                Button(action: saveAsPNG) {
                    Label(transparent ? "투명 PNG로 저장…" : "PNG로 저장…", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(editor.image == nil || editor.isBusy)
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 12)
        }
    }

    private var gptNote: String {
        if !gpt.isReady { return "설정(⌘,)에서 AI 연결 방식을 고르면 쓸 수 있습니다." }
        switch gpt.provider {
        case .codex:
            return "ChatGPT 구독(Codex CLI) · 이미지 도구를 바로 한 번만 부르도록 최소 설정으로 실행합니다. 걸린 시간은 아래 막대에 표시됩니다."
        case .apiKey:
            return "OpenAI API(\(gpt.model)) · 사용량만큼 요금이 나갑니다. 걸린 시간은 아래 막대에 표시됩니다."
        case .higgsfield:
            return "Higgsfield 구독(CLI) · 배경 제거 전용 모델이라 상품은 원본 그대로입니다. 1장에 약 1크레딧. 걸린 시간은 아래 막대에 표시됩니다."
        }
    }

    private func swatch(_ title: String, color: Color, cgColor: CGColor) -> some View {
        Button {
            editor.fillBackground(cgColor)
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25)))
                Text(title).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(6)
        }
        .buttonStyle(DarkButtonStyle())
        .disabled(!editor.hasTransparency || !editor.canEdit)
    }
}
