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
    @ObservedObject var editor: PhotoEditor
    @Binding var cropAspect: CropAspect

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "조정")
            AdjustSlider(title: "밝기", systemImage: "sun.max", value: $adjustments.brightness)
            AdjustSlider(title: "대비", systemImage: "circle.lefthalf.filled", value: $adjustments.contrast)
            AdjustSlider(title: "채도", systemImage: "drop.halffull", value: $adjustments.saturation)

            Button {
                adjustments = ImageAdjustments()
            } label: {
                Label("모두 0으로", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(DarkButtonStyle())
            .disabled(adjustments.isIdentity)
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Text("슬라이더를 움직이면 바로 미리 보이고, '적용'을 누르면 원본 크기로 반영됩니다.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            Spacer()
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
}

private struct AdjustSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(value > 0 ? "+\(Int(value))" : "\(Int(value))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(value == 0 ? Theme.secondaryText : Theme.accent)
            }
            Slider(value: $value, in: -100...100, step: 1)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - AI (GPT로 수정)

private struct AIEditPanel: View {
    @EnvironmentObject private var gpt: GPTSettings
    @ObservedObject var editor: PhotoEditor
    @State private var prompt = ""

    private let examples = [
        "배경을 깔끔한 흰색으로 바꿔줘",
        "조명을 밝고 자연스럽게 보정해줘",
        "제품 사진처럼 그림자를 부드럽게 넣어줘",
        "사진 속 먼지와 잡티를 지워줘"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "GPT로 수정")
                if gpt.hasAPIKey {
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
            Text("원하는 수정을 글로 쓰면 GPT가 사진을 고쳐 줍니다. 먼저 OpenAI API 키를 연결해 주세요.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("ChatGPT 구독과는 별도로, 사용한 만큼 OpenAI에 요금이 나갑니다.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLink {
                Label("설정에서 API 키 연결…", systemImage: "key")
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
                guard let client = gpt.makeClient() else { return }
                editor.gptEdit(client: client, prompt: prompt)
            } label: {
                Label("GPT로 수정하기", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(DarkButtonStyle(prominent: true))
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editor.canEdit)

            Text("모델: \(gpt.model) · 사진이 OpenAI로 전송되고 사용량만큼 요금이 나갑니다. 결과는 '되돌리기'로 취소할 수 있습니다.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - 오려내기 탭의 오른쪽 패널

struct CutOutPanel: View {
    @EnvironmentObject private var gpt: GPTSettings
    @ObservedObject var editor: PhotoEditor
    let saveAsPNG: () -> Void

    @State private var customColor = Color(red: 0.2, green: 0.5, blue: 0.9)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "오려내기 (배경 제거)")
                Text("사진 속 사람·동물·물체를 자동으로 찾아 배경을 지웁니다. macOS에 들어 있는 기능이라 인터넷 연결이 필요 없습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                Button {
                    editor.removeBackground()
                } label: {
                    Label("자동 배경 제거", systemImage: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(DarkButtonStyle(prominent: true))
                .disabled(!editor.canEdit)
                .padding(.horizontal, 12)
                .help("배경 제거 (⇧⌘B)")

                Button {
                    guard let client = gpt.makeClient() else { return }
                    editor.gptEdit(client: client, prompt: PhotoEditor.gptBackgroundRemovalPrompt,
                                   transparentBackground: true)
                } label: {
                    Label("GPT로 배경 제거", systemImage: "sparkles")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(!editor.canEdit || !gpt.hasAPIKey || !gpt.supportsTransparency)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .help("OpenAI로 배경을 지웁니다. 사진이 OpenAI로 전송되고 사용량만큼 요금이 나갑니다.")

                Text(gptNote)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

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
                    Label("투명 PNG로 저장…", systemImage: "square.and.arrow.down")
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
        if !gpt.hasAPIKey { return "GPT로 배경 제거: 설정(⌘,)에서 OpenAI API 키를 연결하면 쓸 수 있습니다." }
        if !gpt.supportsTransparency { return "지금 모델(\(gpt.model))은 투명 배경을 지원하지 않습니다. 설정에서 gpt-image-1.5로 바꿔 주세요." }
        return "GPT(\(gpt.model)): 머리카락 등 어려운 경계에 유리하지만 유료이고 1~2분 걸립니다."
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
