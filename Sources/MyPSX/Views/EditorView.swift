import AppKit
import PSXCore
import SwiftUI

/// 사진 한 장을 크게 보여주고 편집하는 화면
struct EditorView: View {
    @EnvironmentObject private var browser: FolderBrowser
    @StateObject private var editor: PhotoEditor

    @State private var cropAspect: CropAspect = .free
    @State private var showResize = false
    @State private var confirmOverwrite = false

    init(url: URL) {
        _editor = StateObject(wrappedValue: PhotoEditor(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
            if editor.mode == .crop {
                Divider()
                cropBar
            }
            Divider()
            statusBar
        }
        .task { await editor.load() }
        .onChange(of: editor.isModified) { _, modified in
            browser.hasUnsavedEdits = modified
        }
        .onDisappear { browser.hasUnsavedEdits = false }
        .sheet(isPresented: $showResize) {
            if let image = editor.image {
                ResizeSheet(originalSize: image.pixelSize) { width, height in
                    editor.resize(width: width, height: height)
                }
            }
        }
        .confirmationDialog("원본 파일을 덮어쓸까요?", isPresented: $confirmOverwrite) {
            Button("덮어쓰기", role: .destructive) { save(to: editor.sourceURL) }
            Button("다른 이름으로 저장…") { saveAs() }
            Button("취소", role: .cancel) {}
        } message: {
            if editor.overwriteLosesTransparency {
                Text("이 형식은 투명도를 저장할 수 없어 투명한 부분이 흰색으로 저장됩니다. 투명 배경을 유지하려면 '다른 이름으로 저장'에서 PNG를 선택하세요.")
            } else {
                Text("원본 사진이 편집한 사진으로 바뀝니다. 되돌릴 수 없습니다.")
            }
        }
        .alert(
            "오류",
            isPresented: Binding(
                get: { editor.errorMessage != nil },
                set: { if !$0 { editor.errorMessage = nil } }
            )
        ) {
            Button("확인") {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    // MARK: 도구 막대

    /// 창이 좁으면 글자 없이 아이콘만 보여줍니다.
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarContent(showLabels: true)
            toolbarContent(showLabels: false)
        }
    }

    private func toolbarContent(showLabels: Bool) -> some View {
        HStack(spacing: showLabels ? 6 : 2) {
            ToolButton(showLabel: showLabels, title: "목록", systemImage: "square.grid.2x2") {
                browser.requestNavigation { browser.closePhoto() }
            }
            .keyboardShortcut(editor.mode == .crop ? nil : KeyboardShortcut(.escape, modifiers: []))

            ToolButton(showLabel: showLabels, title: "이전", systemImage: "chevron.left") {
                browser.requestNavigation { browser.move(by: -1) }
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!browser.canMove(by: -1) || editor.mode == .crop)

            ToolButton(showLabel: showLabels, title: "다음", systemImage: "chevron.right") {
                browser.requestNavigation { browser.move(by: 1) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!browser.canMove(by: 1) || editor.mode == .crop)

            divider

            Group {
                ToolButton(showLabel: showLabels, title: "왼쪽 회전", systemImage: "rotate.left") {
                    editor.rotate(clockwise: false)
                }
                .keyboardShortcut("[", modifiers: .command)

                ToolButton(showLabel: showLabels, title: "오른쪽 회전", systemImage: "rotate.right") {
                    editor.rotate(clockwise: true)
                }
                .keyboardShortcut("]", modifiers: .command)

                ToolButton(showLabel: showLabels, title: "좌우 반전",
                           systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    editor.flip(horizontal: true)
                }

                ToolButton(showLabel: showLabels, title: "상하 반전",
                           systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                    editor.flip(horizontal: false)
                }

                ToolButton(showLabel: showLabels, title: "자르기", systemImage: "crop") {
                    beginCrop()
                }
                .keyboardShortcut("k", modifiers: .command)

                ToolButton(showLabel: showLabels, title: "크기 조절", systemImage: "arrow.up.left.and.arrow.down.right") {
                    showResize = true
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                ToolButton(showLabel: showLabels, title: "배경 제거", systemImage: "wand.and.stars") {
                    editor.removeBackground()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            .disabled(!editor.canEdit)

            Spacer()

            ToolButton(showLabel: showLabels, title: "실행 취소", systemImage: "arrow.uturn.backward") { editor.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!editor.canUndo || editor.mode == .crop)

            ToolButton(showLabel: showLabels, title: "다시 실행", systemImage: "arrow.uturn.forward") { editor.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!editor.canRedo || editor.mode == .crop)

            divider

            ToolButton(showLabel: showLabels, title: "저장", systemImage: "square.and.arrow.down") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!editor.isModified || editor.isBusy || editor.mode == .crop)

            ToolButton(showLabel: showLabels, title: "다른 이름으로", systemImage: "square.and.arrow.down.on.square") { saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(editor.image == nil || editor.isBusy || editor.mode == .crop)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var divider: some View {
        Divider().frame(height: 28).padding(.horizontal, 4)
    }

    // MARK: 캔버스

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let image = editor.image {
                    let frame = fittedFrame(for: image.pixelSize, in: geo.size)
                    Group {
                        if image.hasAlpha {
                            Checkerboard()
                        }
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.high)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .shadow(color: .black.opacity(0.2), radius: 4)

                    if editor.mode == .crop {
                        CropOverlay(
                            rect: $editor.cropRect,
                            imageSize: image.pixelSize,
                            imageFrame: frame,
                            aspect: cropAspect.ratio(for: image.pixelSize)
                        )
                    }
                } else if let error = editor.loadError {
                    ContentUnavailableView("사진을 열 수 없습니다", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    ProgressView()
                }

                if editor.isBusy {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(editor.busyMessage).font(.callout)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func fittedFrame(for imageSize: CGSize, in container: CGSize) -> CGRect {
        let padding: CGFloat = 24
        let available = CGSize(width: max(container.width - padding * 2, 1),
                               height: max(container.height - padding * 2, 1))
        // 작은 사진은 억지로 키우지 않습니다.
        let scale = min(available.width / imageSize.width, available.height / imageSize.height, 1)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    // MARK: 자르기 막대

    private var cropBar: some View {
        HStack(spacing: 12) {
            Picker("비율", selection: $cropAspect) {
                ForEach(CropAspect.allCases) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .frame(width: 180)

            Text("\(Int(editor.cropRect.width.rounded())) × \(Int(editor.cropRect.height.rounded())) px")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text("드래그해서 영역을 선택하세요")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer()

            Button("취소") { editor.cancelCrop() }
                .keyboardShortcut(.cancelAction)
            Button("자르기 적용") { editor.applyCrop() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onChange(of: cropAspect) { _, aspect in
            guard let image = editor.image else { return }
            editor.resetCropRect(aspect: aspect.ratio(for: image.pixelSize))
        }
    }

    private func beginCrop() {
        guard let image = editor.image else { return }
        editor.beginCrop(aspect: cropAspect.ratio(for: image.pixelSize))
    }

    // MARK: 상태 표시줄

    private var statusBar: some View {
        HStack {
            Text(editor.sourceURL.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            if editor.isModified {
                Text("• 수정됨").foregroundStyle(.orange)
            }
            Spacer()
            if let image = editor.image {
                Text("\(image.width) × \(image.height) px").monospacedDigit()
            }
            if let index = browser.openedPhotoIndex {
                Text("\(index + 1) / \(browser.photos.count)").monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: 저장

    private func save() {
        if editor.canOverwriteOriginal {
            confirmOverwrite = true
        } else {
            saveAs()
        }
    }

    private func saveAs() {
        guard let image = editor.image else { return }
        let source = editor.sourceURL
        let originalExtension = source.pathExtension.lowercased()
        let fileExtension: String
        if image.hasAlpha {
            fileExtension = "png"
        } else if ImageExporter.canWrite(fileExtension: originalExtension) {
            fileExtension = originalExtension
        } else {
            fileExtension = "jpg"
        }

        let panel = NSSavePanel()
        panel.directoryURL = source.deletingLastPathComponent()
        panel.nameFieldStringValue = "\(source.deletingPathExtension().lastPathComponent)_편집.\(fileExtension)"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "투명 배경을 유지하려면 PNG로 저장하세요."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    private func save(to url: URL) {
        Task {
            if await editor.save(to: url) {
                ThumbnailLoader.shared.invalidate(url)
                browser.reload()
            }
        }
    }
}

/// 아이콘 + 짧은 이름으로 된 도구 버튼
private struct ToolButton: View {
    var showLabel = true
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .frame(height: 18)
                if showLabel {
                    Text(title)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(minWidth: showLabel ? 46 : 30, minHeight: 34)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

/// 투명한 부분을 보여주는 체크무늬 배경
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var path = Path()
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    path.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
            context.fill(path, with: .color(Color(white: 0.85)))
        }
    }
}
