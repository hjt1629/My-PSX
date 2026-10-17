import AppKit
import PSXCore
import SwiftUI

// MARK: - 사진 편집 탭의 오른쪽 패널

struct EditPanel: View {
    @ObservedObject var editor: PhotoEditor
    @Binding var cropAspect: CropAspect
    @Binding var tool: EditTool?
    let onRemoveBackground: () -> Void

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
            toolList
        }
    }

    private var toolList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                PanelHeader(title: "기본")
                ToolRow(title: "자르기", systemImage: "crop", shortcut: "⌘K") {
                    guard let image = editor.image else { return }
                    editor.beginCrop(aspect: cropAspect.ratio(for: image.pixelSize))
                }
                ToolRow(title: "크기 조절", systemImage: "arrow.up.left.and.arrow.down.right", shortcut: "⌥⌘I") {
                    tool = .resize
                }

                PanelHeader(title: "회전")
                HStack(spacing: 6) {
                    RotateButton(title: "왼쪽 90°", systemImage: "rotate.left") {
                        editor.rotate(clockwise: false)
                    }
                    .help("왼쪽으로 회전 (⌘[)")
                    RotateButton(title: "오른쪽 90°", systemImage: "rotate.right") {
                        editor.rotate(clockwise: true)
                    }
                    .help("오른쪽으로 회전 (⌘])")
                    RotateButton(title: "좌우 반전",
                                 systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                        editor.flip(horizontal: true)
                    }
                    RotateButton(title: "상하 반전",
                                 systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                        editor.flip(horizontal: false)
                    }
                }
                .padding(.horizontal, 10)

                PanelHeader(title: "도구")
                ToolRow(title: "배경 제거 (누끼)", systemImage: "scissors", shortcut: "⇧⌘B") {
                    onRemoveBackground()
                }
            }
            .padding(.bottom, 12)
        }
        .disabled(!editor.canEdit)
    }
}

/// 패널 안의 한 줄짜리 큰 버튼
private struct ToolRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(DarkButtonStyle())
        .padding(.horizontal, 6)
    }
}

/// 회전 영역의 네모 버튼
private struct RotateButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(DarkButtonStyle())
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

// MARK: - 누끼 탭의 오른쪽 패널

struct CutOutPanel: View {
    @ObservedObject var editor: PhotoEditor
    let saveAsPNG: () -> Void

    @State private var customColor = Color(red: 0.2, green: 0.5, blue: 0.9)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "누끼 (배경 제거)")
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
