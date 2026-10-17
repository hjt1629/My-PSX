import AppKit
import PSXCore
import SwiftUI

/// 사진 편집 / 오려내기 탭: 왼쪽 파일 탐색(폴더 트리 + 썸네일) + 가운데 사진 + 오른쪽 도구 패널
struct EditorWorkspace: View {
    @EnvironmentObject private var browser: FolderBrowser
    /// 왼쪽 패널 너비 (뷰어와 편집 탭이 함께 사용)
    @AppStorage("leftPaneWidth") private var leftWidth: Double = 280

    var body: some View {
        HStack(spacing: 0) {
            EditorBrowserPane()
                .frame(width: leftWidth)
            ResizeHandle(width: $leftWidth, range: 200...460, defaultWidth: 280)
            if let editor = browser.editor {
                EditorContent(editor: editor)
                    .id(ObjectIdentifier(editor))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.secondaryText)
                    Text("편집할 사진을 고르세요")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("왼쪽 썸네일을 누르면 여기에서 편집합니다.")
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
                .background {
                    Button("") { browser.tab = .viewer }
                        .keyboardShortcut(.escape, modifiers: [])
                        .opacity(0)
                        .allowsHitTesting(false)
                }
            }
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
    @AppStorage("cutoutTransparent") private var cutoutTransparent = false
    @AppStorage("cutoutLargestOnly") private var cutoutLargestOnly = true
    @AppStorage("cutoutSharpen") private var cutoutSharpen = 30.0
    @EnvironmentObject private var gpt: GPTSettings
    @AppStorage("rightPanelWidth") private var rightWidth: Double = 270
    @StateObject private var zoom = CanvasZoom()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                PanelDivider(vertical: false)
                EditorCanvas(editor: editor, zoom: zoom, cropAspect: cropAspect, showingOriginal: showingOriginal)
                PanelDivider(vertical: false)
                bottomBar
            }
            ResizeHandle(width: $rightWidth, range: 250...420, defaultWidth: 270, trailing: true)
            Group {
                if browser.tab == .cutout {
                    CutOutPanel(editor: editor, saveAsPNG: { saveAs(forcePNG: true) })
                } else {
                    EditPanel(editor: editor, cropAspect: $cropAspect, tool: $tool) {
                        removeBackgroundQuickly()
                    }
                }
            }
            .frame(width: rightWidth)
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

    private var isToolActive: Bool { editor.mode == .crop || tool != nil || editor.isAdjusting }

    // MARK: 위 막대 (✕ < > 파일 이름)

    private var topBar: some View {
        HStack(spacing: 4) {
            topButton("xmark", help: "사진 닫기") {
                browser.requestNavigation { browser.closePhoto() }
            }
            topButton("chevron.left", help: "이전 사진 (←)") { navigate(-1) }
                .disabled(!browser.canMove(by: -1) || isToolActive)
            topButton("chevron.right", help: "다음 사진 (→)") { navigate(1) }
                .disabled(!browser.canMove(by: 1) || isToolActive)
            Text(editor.sourceURL.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 6)
                .help(editor.sourceURL.path)
            if editor.isModified {
                Text("· 수정됨")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.panel)
    }

    private func topButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(DarkButtonStyle())
        .help(help)
    }

    // MARK: 아래 막대

    private var bottomBar: some View {
        HStack(spacing: 6) {
            if let image = editor.image {
                Text("\(image.width) × \(image.height)").monospacedDigit().lineLimit(1)
            }
            if let index = browser.openedPhotoIndex {
                Text("· \(index + 1) / \(browser.photos.count)").monospacedDigit().lineLimit(1)
            }
            if let timing = editor.lastTiming {
                Text("· \(timing)").monospacedDigit().lineLimit(1)
                    .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 12)

            // 좁은 창에서는 글자 없이 아이콘만 보여줍니다.
            ViewThatFits(in: .horizontal) {
                barActions(showLabels: true)
                barActions(showLabels: false)
            }
            .layoutPriority(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.panel)
    }

    private func barActions(showLabels: Bool) -> some View {
        HStack(spacing: 6) {
            // 누르고 있는 동안 편집 전 사진을 보여줍니다.
            Group {
                if showLabels {
                    Label("원본 비교", systemImage: "square.split.2x1")
                } else {
                    Image(systemName: "square.split.2x1")
                }
            }
            .fixedSize()
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

            BarButton(title: "되돌리기", systemImage: "arrow.uturn.backward", showLabel: showLabels) { editor.undo() }
                .disabled(!editor.canUndo || isToolActive)
            BarButton(title: "다시하기", systemImage: "arrow.uturn.forward", showLabel: showLabels) { editor.redo() }
                .disabled(!editor.canRedo || isToolActive)
            BarButton(title: "원래대로", systemImage: "clock.arrow.circlepath", showLabel: showLabels) {
                editor.revertToSaved()
            }
            .disabled(!editor.isModified || editor.isBusy || isToolActive)

            barDivider

            BarButton(title: "다른 이름으로", systemImage: "square.and.arrow.down.on.square", showLabel: showLabels) {
                saveAs()
            }
            .disabled(editor.image == nil || editor.isBusy || isToolActive)
            BarButton(title: "저장", systemImage: "square.and.arrow.down", showLabel: showLabels, prominent: true) {
                save()
            }
            .disabled(!editor.isModified || editor.isBusy || isToolActive)
        }
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
                Button("") { removeBackgroundQuickly() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("") {
                    browser.tab = .cutout
                    editor.removeBackground(transparent: cutoutTransparent, largestOnly: cutoutLargestOnly)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
            .disabled(!editor.canEdit || tool != nil)
            // 확대 / 축소는 자르기 중에도 됩니다.
            Group {
                Button("") { zoom.zoom(by: 1.25) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("") { zoom.zoom(by: 0.8) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("") { zoom.reset() }
                    .keyboardShortcut("0", modifiers: .command)
            }
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

    /// ⇧⌘B: GPT를 쓸 수 있으면 GPT 빠른 배경 제거, 아니면 맥 AI로
    private func removeBackgroundQuickly() {
        browser.tab = .cutout
        if gpt.isReady, let ai = gpt.makeEditor() {
            editor.aiRemoveBackground(ai, transparent: cutoutTransparent, sharpen: cutoutSharpen)
        } else {
            editor.removeBackground(transparent: cutoutTransparent, largestOnly: cutoutLargestOnly)
        }
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
    var showLabel = true
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if showLabel {
                    Label(title, systemImage: systemImage)
                } else {
                    Image(systemName: systemImage)
                }
            }
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(DarkButtonStyle(prominent: prominent))
        .help(title)
    }
}

// MARK: - 왼쪽 파일 탐색

/// 사진 편집 탭의 왼쪽: 위쪽 폴더 트리 + 아래쪽 현재 폴더 썸네일 + 맨 아래 아이콘 줄
private struct EditorBrowserPane: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        VStack(spacing: 0) {
            // 위아래 경계를 끌어서 트리와 썸네일 영역의 크기를 바꿀 수 있습니다.
            VSplitView {
                FolderTreePane(showsOpenButton: false)
                    .frame(maxWidth: .infinity, minHeight: 120, idealHeight: 360, maxHeight: .infinity)
                EditorThumbnails()
                    .frame(maxWidth: .infinity, minHeight: 120, idealHeight: 300, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            PanelDivider(vertical: false)
            HStack(spacing: 2) {
                favoriteButton
                paneButton("arrow.clockwise", help: "새로고침") { browser.reload() }
                paneButton("arrow.left", help: "뒤로") { browser.goBack() }
                    .disabled(!browser.canGoBack)
                paneButton("arrow.right", help: "앞으로") { browser.goForward() }
                    .disabled(!browser.canGoForward)
                paneButton("arrow.up", help: "상위 폴더") { browser.goUp() }
                    .disabled(!browser.canGoUp)
                Spacer()
                paneButton("folder.badge.plus", help: "폴더 열기…") { browser.chooseFolder() }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .background(Theme.panel)
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if let folder = browser.currentFolder {
            let isFavorite = browser.isFavorite(folder)
            paneButton(isFavorite ? "star.fill" : "star",
                       help: isFavorite ? "즐겨찾기에서 제거" : "즐겨찾기에 추가",
                       tint: isFavorite ? Color.yellow : Theme.text) {
                browser.toggleFavorite(folder)
            }
        }
    }

    private func paneButton(_ systemImage: String, help: String, tint: Color = Theme.text,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(DarkButtonStyle())
        .help(help)
    }
}

/// 현재 폴더의 사진 썸네일. 누르면 그 사진을 편집합니다.
private struct EditorThumbnails: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        Group {
            if browser.photos.isEmpty {
                Text(browser.isLoading ? "불러오는 중…" : "이 폴더에는 사진이 없습니다")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                            ForEach(browser.photos, id: \.self) { url in
                                EditorThumbnailCell(url: url, isOpen: url == browser.openedPhoto)
                                    .id(url)
                                    .onTapGesture { open(url) }
                            }
                        }
                        .padding(8)
                    }
                    .onAppear { scroll(proxy, animated: false) }
                    .onChange(of: browser.openedPhoto) { _, _ in scroll(proxy, animated: true) }
                }
            }
        }
        .background(Color.black.opacity(0.12))
    }

    private func open(_ url: URL) {
        guard url != browser.openedPhoto else { return }
        browser.requestNavigation { browser.openPhoto(url, in: browser.tab) }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let url = browser.openedPhoto, browser.photos.contains(url) else { return }
        if animated {
            withAnimation { proxy.scrollTo(url) }
        } else {
            proxy.scrollTo(url, anchor: .center)
        }
    }
}

/// 썸네일 한 칸
private struct EditorThumbnailCell: View {
    let url: URL
    let isOpen: Bool

    var body: some View {
        // 고른 사진은 포토스케이프 X처럼 파란 칸 + 크기 표시 + 파일 이름
        VStack(spacing: 3) {
            ThumbnailView(url: url)
                .frame(width: 66, height: isOpen ? 50 : 66)
                .overlay(alignment: .bottom) {
                    if isOpen { PixelSizeBadge(url: url) }
                }
            if isOpen {
                Text(url.lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 66, height: 13)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 3).fill(isOpen ? Theme.accent : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isOpen ? Theme.accent : Color.white.opacity(0.08)))
        .contentShape(Rectangle())
        .help(url.lastPathComponent)
    }
}

// MARK: - 캔버스

private struct EditorCanvas: View {
    @ObservedObject var editor: PhotoEditor
    @ObservedObject var zoom: CanvasZoom
    let cropAspect: CropAspect
    let showingOriginal: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.canvas

                if let image = displayedImage, let size = layoutSize {
                    let fitted = fittedFrame(for: size, in: geo.size)
                    let frame = zoom.frame(fitted: fitted)
                    let pixelScale = frame.width / size.width
                    Group {
                        if image.hasAlpha {
                            Checkerboard()
                        }
                        Image(decorative: image, scale: 1)
                            .resizable()
                            // 크게 확대하면 픽셀이 또렷하게 보이도록
                            .interpolation(pixelScale >= 3 ? .none : .high)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .shadow(color: .black.opacity(0.6), radius: 8)

                    if editor.mode == .crop && !showingOriginal {
                        CropOverlay(
                            rect: $editor.cropRect,
                            imageSize: size,
                            imageFrame: frame,
                            aspect: cropAspect.ratio(for: size)
                        )
                    }
                    if zoom.isZoomed {
                        Button { zoom.reset() } label: {
                            Text("\(Int((pixelScale * 100).rounded()))% · 맞춤")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .help("화면에 맞춤 (⌘0)")
                        .position(x: geo.size.width - 60, y: geo.size.height - 20)
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
            .clipped()
            .background {
                // 트랙패드: 핀치 = 확대/축소, 두 손가락 스크롤 = 이동 / 마우스 휠, ⌘+스크롤 = 확대/축소
                CanvasEventCatcher(
                    onMagnify: { magnification, point in
                        prepareZoom(in: geo.size)
                        zoom.zoom(by: 1 + magnification, anchor: point)
                    },
                    onScroll: { event, point in
                        prepareZoom(in: geo.size)
                        if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
                            zoom.zoom(by: exp(event.scrollingDeltaY * step), anchor: point)
                            return true
                        }
                        guard zoom.scale > 1 else { return false }
                        zoom.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                        return true
                    }
                )
            }
            .onAppear { prepareZoom(in: geo.size) }
            .onChange(of: geo.size) { _, size in prepareZoom(in: size) }
            .onChange(of: layoutSize) { _, _ in
                zoom.reset()
                prepareZoom(in: geo.size)
            }
        }
    }

    /// 확대 계산에 필요한 지금의 캔버스 / 맞춤 크기
    private func prepareZoom(in viewport: CGSize) {
        zoom.viewport = viewport
        zoom.fittedSize = layoutSize.map { fittedFrame(for: $0, in: viewport).size } ?? .zero
    }

    private var displayedImage: CGImage? {
        if showingOriginal { return editor.originalImage ?? editor.image }
        return editor.previewImage ?? editor.image
    }

    /// 화면 배치는 항상 원본 크기 기준 (미리보기는 작게 줄인 이미지라서)
    private var layoutSize: CGSize? {
        if showingOriginal, let original = editor.originalImage { return original.pixelSize }
        return editor.image?.pixelSize
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
