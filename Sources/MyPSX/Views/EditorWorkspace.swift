import AppKit
import PSXCore
import SwiftUI

/// 사진 편집 / 누끼 탭: 왼쪽 필름스트립 + 가운데 캔버스 + 오른쪽 도구 패널 + 아래 막대
struct EditorWorkspace: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        if let editor = browser.editor {
            EditorContent(editor: editor)
                .id(ObjectIdentifier(editor))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.secondaryText)
                Text("편집할 사진이 없습니다")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("뷰어에서 사진을 더블클릭하세요.")
                    .foregroundStyle(Theme.secondaryText)
                Button("뷰어로 가기") { browser.tab = .viewer }
                    .buttonStyle(DarkButtonStyle(prominent: true))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
    }
}

/// 오른쪽 패널에 열린 도구
enum EditTool {
    case resize
}

private struct EditorContent: View {
    @EnvironmentObject private var browser: FolderBrowser
    @ObservedObject var editor: PhotoEditor

    @State private var cropAspect: CropAspect = .free
    @State private var tool: EditTool?
    @State private var showingOriginal = false
    @State private var confirmOverwrite = false

    var body: some View {
        HStack(spacing: 0) {
            Filmstrip()
                .frame(width: 112)
            PanelDivider()
            VStack(spacing: 0) {
                EditorCanvas(editor: editor, cropAspect: cropAspect, showingOriginal: showingOriginal)
                PanelDivider(vertical: false)
                bottomBar
            }
            PanelDivider()
            Group {
                if browser.tab == .cutout {
                    CutOutPanel(editor: editor, saveAsPNG: { saveAs(forcePNG: true) })
                } else {
                    EditPanel(editor: editor, cropAspect: $cropAspect, tool: $tool) {
                        browser.tab = .cutout
                        editor.removeBackground()
                    }
                }
            }
            .frame(width: 270)
            .background(Theme.panel)
        }
        .background { shortcuts }
        .onAppear { browser.hasUnsavedEdits = editor.isModified }
        .onChange(of: editor.isModified) { _, modified in
            browser.hasUnsavedEdits = modified
        }
        .onChange(of: browser.tab) { _, newTab in
            // 사진 편집 탭을 떠나면 열려 있던 도구를 닫습니다.
            guard newTab != .editor else { return }
            tool = nil
            if editor.mode == .crop { editor.cancelCrop() }
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

    private var isToolActive: Bool { editor.mode == .crop || tool != nil }

    // MARK: 아래 막대

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Text(editor.sourceURL.lastPathComponent)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            if let image = editor.image {
                Text("\(image.width) × \(image.height)").monospacedDigit()
            }
            if let index = browser.openedPhotoIndex {
                Text("· \(index + 1) / \(browser.photos.count)").monospacedDigit()
            }
            if editor.isModified {
                Text("· 수정됨").foregroundStyle(.orange)
            }

            Spacer(minLength: 12)

            // 누르고 있는 동안 편집 전 사진을 보여줍니다.
            Label("원본 비교", systemImage: "square.split.2x1")
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(showingOriginal ? Theme.accent.opacity(0.55) : Theme.raised)
                )
                .foregroundStyle(Theme.text)
                .opacity(editor.isModified ? 1 : 0.4)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if editor.isModified { showingOriginal = true } }
                        .onEnded { _ in showingOriginal = false }
                )
                .help("누르고 있으면 편집 전 사진을 보여줍니다")

            barDivider

            BarButton(title: "되돌리기", systemImage: "arrow.uturn.backward") { editor.undo() }
                .disabled(!editor.canUndo || isToolActive)
            BarButton(title: "다시하기", systemImage: "arrow.uturn.forward") { editor.redo() }
                .disabled(!editor.canRedo || isToolActive)
            BarButton(title: "원래대로", systemImage: "clock.arrow.circlepath") { editor.revertToSaved() }
                .disabled(!editor.isModified || editor.isBusy || isToolActive)

            barDivider

            BarButton(title: "다른 이름으로", systemImage: "square.and.arrow.down.on.square") { saveAs() }
                .disabled(editor.image == nil || editor.isBusy || isToolActive)
            BarButton(title: "저장", systemImage: "square.and.arrow.down", prominent: true) { save() }
                .disabled(!editor.isModified || editor.isBusy || isToolActive)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.panel)
    }

    private var barDivider: some View {
        Theme.separator.frame(width: 1, height: 20).padding(.horizontal, 4)
    }

    // MARK: 단축키 (화면에는 보이지 않음)

    private var shortcuts: some View {
        ZStack {
            Button("") { escape() }
                .keyboardShortcut(.escape, modifiers: [])
            Group {
                Button("") { navigate(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!browser.canMove(by: -1))
                Button("") { navigate(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!browser.canMove(by: 1))
                Button("") { editor.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!editor.canUndo)
                Button("") { editor.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!editor.canRedo)
                Button("") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!editor.isModified || editor.isBusy)
                Button("") { saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(editor.image == nil || editor.isBusy)
            }
            .disabled(isToolActive)
            Group {
                Button("") { editor.rotate(clockwise: false) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("") { editor.rotate(clockwise: true) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("") { beginCrop() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { browser.tab = .editor; tool = .resize }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button("") {
                    browser.tab = .cutout
                    editor.removeBackground()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            .disabled(!editor.canEdit || tool != nil)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func escape() {
        if editor.mode == .crop {
            editor.cancelCrop()
        } else if tool != nil {
            tool = nil
        } else {
            browser.tab = .viewer
        }
    }

    private func navigate(_ offset: Int) {
        browser.requestNavigation { browser.move(by: offset) }
    }

    private func beginCrop() {
        guard let image = editor.image else { return }
        browser.tab = .editor
        editor.beginCrop(aspect: cropAspect.ratio(for: image.pixelSize))
    }

    // MARK: 저장

    private func save() {
        if editor.canOverwriteOriginal {
            confirmOverwrite = true
        } else {
            saveAs()
        }
    }

    private func saveAs(forcePNG: Bool = false) {
        guard let image = editor.image else { return }
        let source = editor.sourceURL
        let originalExtension = source.pathExtension.lowercased()
        let fileExtension: String
        if forcePNG || image.hasAlpha {
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

/// 아래 막대의 아이콘 + 글자 버튼
private struct BarButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(DarkButtonStyle(prominent: prominent))
        .help(title)
    }
}

// MARK: - 필름스트립

/// 왼쪽: 같은 폴더의 사진 목록
private struct Filmstrip: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(browser.photos, id: \.self) { url in
                        let isOpen = url == browser.openedPhoto
                        ThumbnailView(url: url)
                            .frame(width: 84, height: 84)
                            .padding(5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isOpen ? Theme.accent.opacity(0.35) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isOpen ? Theme.accent : .clear, lineWidth: 2)
                            )
                            .contentShape(Rectangle())
                            .id(url)
                            .help(url.lastPathComponent)
                            .onTapGesture {
                                guard !isOpen else { return }
                                browser.requestNavigation { browser.openPhoto(url, in: browser.tab) }
                            }
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: browser.openedPhoto) { _, _ in scroll(proxy, animated: true) }
        }
        .background(Theme.panel)
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let url = browser.openedPhoto else { return }
        if animated {
            withAnimation { proxy.scrollTo(url, anchor: .center) }
        } else {
            proxy.scrollTo(url, anchor: .center)
        }
    }
}

// MARK: - 캔버스

private struct EditorCanvas: View {
    @ObservedObject var editor: PhotoEditor
    let cropAspect: CropAspect
    let showingOriginal: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.canvas

                if let image = displayedImage {
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
                    .shadow(color: .black.opacity(0.6), radius: 8)

                    if editor.mode == .crop && !showingOriginal {
                        CropOverlay(
                            rect: $editor.cropRect,
                            imageSize: image.pixelSize,
                            imageFrame: frame,
                            aspect: cropAspect.ratio(for: image.pixelSize)
                        )
                    }
                    if showingOriginal {
                        Text("원본")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .position(x: geo.size.width / 2, y: 22)
                    }
                } else if let error = editor.loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                        Text("사진을 열 수 없습니다").font(.headline)
                        Text(error).font(.caption)
                    }
                    .foregroundStyle(Theme.secondaryText)
                } else {
                    ProgressView()
                }

                if editor.isBusy {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(editor.busyMessage).font(.callout)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(22)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.75)))
                }
            }
        }
    }

    private var displayedImage: CGImage? {
        showingOriginal ? (editor.originalImage ?? editor.image) : editor.image
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
}
