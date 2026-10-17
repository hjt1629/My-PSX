import PSXCore
import SwiftUI

/// 뷰어 탭: 왼쪽 폴더 트리 + 가운데 썸네일(또는 크게 보기) + 아래 상태 막대
struct ViewerView: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        HStack(spacing: 0) {
            FolderTreePane()
                .frame(width: 280)
            PanelDivider()
            VStack(spacing: 0) {
                PathBar()
                PanelDivider(vertical: false)
                if let preview = browser.previewPhoto {
                    PhotoPreview(url: preview)
                } else {
                    ThumbnailGrid()
                }
                PanelDivider(vertical: false)
                ViewerStatusBar()
            }
        }
    }
}

// MARK: - 폴더 트리

/// 왼쪽 폴더 트리. 위쪽 "폴더 | 즐겨찾기"로 보기를 바꿉니다. (뷰어 / 사진 편집 탭이 함께 사용)
struct FolderTreePane: View {
    @EnvironmentObject private var browser: FolderBrowser
    var showsOpenButton = true
    @AppStorage("folderTreeMode") private var mode = TreeMode.folders.rawValue

    enum TreeMode: String, CaseIterable {
        case folders, favorites

        var title: String {
            switch self {
            case .folders: return "폴더"
            case .favorites: return "즐겨찾기"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(TreeMode.allCases.enumerated()), id: \.element) { index, item in
                    if index > 0 {
                        Color.white.opacity(0.15).frame(width: 1, height: 12)
                    }
                    Button {
                        mode = item.rawValue
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: mode == item.rawValue ? .semibold : .regular))
                            .foregroundStyle(mode == item.rawValue ? Theme.accent : Theme.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            PanelDivider(vertical: false)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if mode == TreeMode.favorites.rawValue {
                            if browser.favorites.isEmpty {
                                Text("폴더에서 마우스 오른쪽 버튼 → 즐겨찾기에 추가")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                                    .padding(14)
                            }
                            ForEach(browser.favorites, id: \.self) { url in
                                row(url, icon: "star.fill", iconColor: .yellow)
                            }
                        } else {
                            PanelHeader(title: "위치")
                            ForEach(browser.standardLocations, id: \.self) { url in
                                row(url, icon: icon(for: url), iconColor: Theme.folder)
                            }

                            PanelHeader(title: "볼륨")
                            ForEach(browser.volumes, id: \.self) { url in
                                row(url, icon: url.path == "/" ? "internaldrive.fill" : "externaldrive.fill",
                                    iconColor: Theme.secondaryText)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: browser.currentFolder) { _, folder in
                    scroll(proxy, to: folder)
                }
                .onAppear { scroll(proxy, to: browser.currentFolder) }
            }

            if showsOpenButton {
                PanelDivider(vertical: false)
                Button {
                    browser.chooseFolder()
                } label: {
                    Label("폴더 열기…", systemImage: "folder.badge.plus")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(8)
            }
        }
        .background(Theme.panel)
    }

    private func row(_ url: URL, icon: String, iconColor: Color) -> some View {
        FolderTreeRow(url: url, depth: 0, icon: icon, iconColor: iconColor,
                      revealTarget: url == revealRoot ? browser.currentFolder : nil)
    }

    /// 지금 폴더를 품고 있는 가장 가까운 최상위 항목 하나만 자동으로 펼칩니다.
    private var revealRoot: URL? {
        guard let current = browser.currentFolder else { return nil }
        let roots = mode == TreeMode.favorites.rawValue
            ? browser.favorites
            : browser.standardLocations + browser.volumes
        return roots
            .filter { $0.contains(current) }
            .max { $0.resolvedPath.count < $1.resolvedPath.count }
    }

    private func scroll(_ proxy: ScrollViewProxy, to folder: URL?) {
        guard let folder else { return }
        // 하위 폴더를 불러와 펼치는 시간을 잠깐 기다린 뒤 스크롤합니다.
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation { proxy.scrollTo(folder.resolvedPath, anchor: .center) }
        }
    }

    private func icon(for url: URL) -> String {
        let fileManager = FileManager.default
        func standard(_ directory: FileManager.SearchPathDirectory) -> URL? {
            fileManager.urls(for: directory, in: .userDomainMask).first?.normalizedFolder
        }
        let url = url.normalizedFolder
        if url == fileManager.homeDirectoryForCurrentUser.normalizedFolder { return "house.fill" }
        if url == standard(.picturesDirectory) { return "photo.fill" }
        if url == standard(.desktopDirectory) { return "menubar.dock.rectangle" }
        if url == standard(.documentDirectory) { return "doc.fill" }
        if url == standard(.downloadsDirectory) { return "arrow.down.circle.fill" }
        return "folder.fill"
    }
}

/// 트리의 한 줄. 화살표를 누르면 하위 폴더를 불러와 펼칩니다.
/// revealTarget이 이 폴더 아래에 있으면 저절로 펼쳐서 그 폴더까지 보여줍니다.
private struct FolderTreeRow: View {
    @EnvironmentObject private var browser: FolderBrowser
    let url: URL
    let depth: Int
    var icon = "folder.fill"
    var iconColor = Theme.folder
    var revealTarget: URL?

    @State private var expanded = false
    @State private var children: [URL]?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Button {
                    toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .opacity(children?.isEmpty == true ? 0 : 1)

                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrent ? Color.white : iconColor)
                    .frame(width: 16)
                Text(url.displayName)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isCurrent ? Color.white : Theme.text)
            .padding(.leading, CGFloat(depth) * 14 + 6)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(rowBackground)
            .contentShape(Rectangle())
            .id(url.resolvedPath)
            .onHover { hovering = $0 }
            .onTapGesture {
                browser.requestNavigation { browser.open(folder: url) }
            }
            .contextMenu {
                Button(browser.isFavorite(url) ? "즐겨찾기에서 제거" : "즐겨찾기에 추가") {
                    browser.toggleFavorite(url)
                }
                Button("Finder에서 보기") { browser.revealInFinder(url) }
            }
            .help(url.path)

            if expanded, let children {
                ForEach(children, id: \.self) { child in
                    FolderTreeRow(url: child, depth: depth + 1,
                                  revealTarget: revealTarget.flatMap { child.contains($0) ? $0 : nil })
                }
            }
        }
        .onAppear { revealIfNeeded() }
        .onChange(of: revealTarget) { _, _ in revealIfNeeded() }
    }

    private var isCurrent: Bool {
        guard let current = browser.currentFolder else { return false }
        return current.resolvedPath == url.resolvedPath
    }

    private var rowBackground: Color {
        if isCurrent { return Theme.accent.opacity(0.75) }
        return hovering ? Theme.hover : .clear
    }

    private func revealIfNeeded() {
        guard let target = revealTarget, !expanded,
              url.contains(target), url.resolvedPath != target.resolvedPath else { return }
        expanded = true
        loadChildren()
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() }
        if expanded { loadChildren() }
    }

    private func loadChildren() {
        guard children == nil else { return }
        let folder = url
        Task {
            children = await Task.detached(priority: .userInitiated) {
                FolderBrowser.subfolders(of: folder)
            }.value
        }
    }
}

// MARK: - 위쪽 경로 막대

private struct PathBar: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        HStack(spacing: 4) {
            navButton("chevron.left", help: "뒤로 (⌘[)", enabled: browser.canGoBack) {
                browser.requestNavigation { browser.goBack() }
            }
            .keyboardShortcut("[", modifiers: .command)
            navButton("chevron.right", help: "앞으로 (⌘])", enabled: browser.canGoForward) {
                browser.requestNavigation { browser.goForward() }
            }
            .keyboardShortcut("]", modifiers: .command)
            navButton("arrow.up", help: "상위 폴더 (⌘↑)", enabled: browser.canGoUp) {
                browser.requestNavigation { browser.goUp() }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Theme.separator.frame(width: 1, height: 18).padding(.horizontal, 6)

            Breadcrumb()
                .layoutPriority(-1)

            Spacer(minLength: 8)

            if browser.isLoading {
                ProgressView().controlSize(.small)
            }
            SortMenu()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.panel)
    }

    private func navButton(_ systemImage: String, help: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
        }
        .buttonStyle(DarkButtonStyle())
        .disabled(!enabled)
        .help(help)
    }
}

/// 경로를 폴더 단위 버튼으로 보여줍니다. 누르면 그 폴더로 이동합니다.
private struct Breadcrumb: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        HStack(spacing: 2) {
            let parts = segments
            if parts.count > 5 {
                Text("…").foregroundStyle(Theme.secondaryText)
                chevron
            }
            ForEach(Array(parts.suffix(5).enumerated()), id: \.element) { index, url in
                if index > 0 { chevron }
                let isLast = url == parts.last
                Button {
                    browser.requestNavigation { browser.open(folder: url) }
                } label: {
                    HStack(spacing: 4) {
                        if url.path == "/" {
                            Image(systemName: "internaldrive.fill")
                        } else if url == home {
                            Image(systemName: "house.fill")
                        } else if isLast {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.folder)
                        }
                        Text(url.displayName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                    .foregroundStyle(isLast ? Theme.text : Theme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(isLast)
                .help(url.path)
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.secondaryText.opacity(0.7))
    }

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser.normalizedFolder }

    /// 홈 폴더 안이면 홈부터, 아니면 디스크(/)부터의 폴더 목록
    private var segments: [URL] {
        guard var url = browser.currentFolder else { return [] }
        var result: [URL] = []
        while true {
            result.insert(url, at: 0)
            if url == home || url.path == "/" { break }
            url = url.deletingLastPathComponent().normalizedFolder
        }
        return result
    }
}

/// 정렬 기준 메뉴
private struct SortMenu: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        Menu {
            Picker("정렬 기준", selection: $browser.sort) {
                ForEach(PhotoSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("순서", selection: $browser.sortAscending) {
                Text("오름차순").tag(true)
                Text("내림차순").tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label("정렬: \(browser.sort.title)", systemImage: "arrow.up.arrow.down")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(Theme.text)
        .help("사진 정렬")
    }
}

// MARK: - 썸네일 격자

private struct ThumbnailGrid: View {
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 150
    /// 한 줄에 들어가는 칸 수 (↑ / ↓ 이동에 사용)
    @State private var columns = 1

    private let spacing: CGFloat = 6
    private let padding: CGFloat = 12

    var body: some View {
        Group {
            if browser.currentFolder == nil {
                emptyState(title: "폴더를 선택하세요", systemImage: "folder",
                           message: "왼쪽에서 사진이 들어 있는 폴더를 고르세요.")
            } else if browser.subfolders.isEmpty && browser.photos.isEmpty {
                if browser.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState(title: "사진이 없습니다", systemImage: "photo.on.rectangle",
                               message: "이 폴더에는 사진이나 하위 폴더가 없습니다.")
                }
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
    }

    private func emptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            Text(message).foregroundStyle(Theme.secondaryText)
            Button("폴더 열기…") { browser.chooseFolder() }
                .buttonStyle(DarkButtonStyle(prominent: true))
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        let size = CGFloat(thumbnailSize)
        return GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 16), spacing: spacing)],
                              spacing: spacing) {
                        ForEach(browser.subfolders, id: \.self) { folder in
                            FolderTile(url: folder, size: size)
                                .onTapGesture(count: 2) {
                                    browser.open(folder: folder)
                                }
                                .contextMenu {
                                    Button("열기") { browser.open(folder: folder) }
                                    Button(browser.isFavorite(folder) ? "즐겨찾기에서 제거" : "즐겨찾기에 추가") {
                                        browser.toggleFavorite(folder)
                                    }
                                    Button("Finder에서 보기") { browser.revealInFinder(folder) }
                                }
                        }
                        ForEach(browser.photos, id: \.self) { photo in
                            PhotoTile(url: photo, size: size, isSelected: browser.selectedPhoto == photo)
                                .id(photo)
                                .onTapGesture(count: 2) {
                                    browser.preview(photo)
                                }
                                .onTapGesture {
                                    browser.selectedPhoto = photo
                                }
                                .contextMenu {
                                    Button("크게 보기") { browser.preview(photo) }
                                    Button("사진 편집") { browser.openPhoto(photo, in: .editor) }
                                    Button("오려내기 (배경 제거)") { browser.openPhoto(photo, in: .cutout) }
                                    Divider()
                                    Button("Finder에서 보기") { browser.revealInFinder(photo) }
                                }
                        }
                    }
                    .padding(padding)
                }
                .onChange(of: browser.selectedPhoto) { _, photo in
                    if let photo { proxy.scrollTo(photo) }
                }
            }
            .onAppear { updateColumns(width: geo.size.width, size: size) }
            .onChange(of: geo.size.width) { _, width in updateColumns(width: width, size: size) }
            .onChange(of: thumbnailSize) { _, _ in updateColumns(width: geo.size.width, size: size) }
        }
        .id(browser.currentFolder)
        .background { keyboard }
    }

    /// LazyVGrid(.adaptive)와 같은 방식으로 한 줄 칸 수를 계산합니다.
    private func updateColumns(width: CGFloat, size: CGFloat) {
        let available = width - padding * 2
        let item = size + 16
        columns = max(1, Int((available + spacing) / (item + spacing)))
    }

    /// 방향키로 선택 이동, Return / Space로 크게 보기 (화면에는 보이지 않음)
    private var keyboard: some View {
        ZStack {
            Button("") { browser.moveSelection(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { browser.moveSelection(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { moveVertically(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("") { moveVertically(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { previewSelected() }
                .keyboardShortcut(.return, modifiers: [])
            Button("") { previewSelected() }
                .keyboardShortcut(.space, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    /// 폴더 칸까지 포함한 격자 위치 기준으로 위아래 이동
    private func moveVertically(_ direction: Int) {
        guard let selected = browser.selectedPhoto,
              let index = browser.photos.firstIndex(of: selected) else {
            browser.moveSelection(by: 0)
            return
        }
        let position = browser.subfolders.count + index + direction * columns
        let target = min(max(position - browser.subfolders.count, 0), browser.photos.count - 1)
        browser.moveSelection(by: target - index)
    }

    private func previewSelected() {
        if browser.selectedPhoto == nil { browser.moveSelection(by: 0) }
        if let selected = browser.selectedPhoto { browser.preview(selected) }
    }
}

private struct FolderTile: View {
    let url: URL
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.folder.opacity(0.85))
                .padding(size * 0.2)
                .frame(width: size, height: size)
            Text(url.lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: size)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(url.lastPathComponent)
    }
}

private struct PhotoTile: View {
    let url: URL
    let size: CGFloat
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            ThumbnailView(url: url)
                .frame(width: size, height: size)
            Text(url.lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: size)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.accent.opacity(0.4) : (hovering ? Theme.hover : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(url.lastPathComponent)
    }
}

// MARK: - 크게 보기

/// 뷰어 안에서 사진 한 장을 크게 보여줍니다. ← / → 로 넘기고 Esc로 목록에 돌아갑니다.
private struct PhotoPreview: View {
    @EnvironmentObject private var browser: FolderBrowser
    let url: URL
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.canvas

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 24)
                    .onTapGesture(count: 2) { browser.closePreview() }
            } else if failed {
                Label("사진을 열 수 없습니다", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ProgressView()
            }

            HStack {
                sideButton("chevron.left", enabled: index.map { $0 > 0 } ?? false) {
                    browser.moveSelection(by: -1)
                }
                Spacer()
                sideButton("chevron.right", enabled: index.map { $0 < browser.photos.count - 1 } ?? false) {
                    browser.moveSelection(by: 1)
                }
            }
            .padding(.horizontal, 12)

            VStack {
                HStack(spacing: 8) {
                    Button {
                        browser.closePreview()
                    } label: {
                        Label("목록", systemImage: "square.grid.2x2")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(DarkButtonStyle())
                    .help("목록으로 (Esc)")

                    Spacer()
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if let index {
                        Text("\(index + 1) / \(browser.photos.count)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()

                    Button {
                        browser.openPhoto(url, in: .editor)
                    } label: {
                        Label("사진 편집", systemImage: AppTab.editor.systemImage)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(DarkButtonStyle(prominent: true))
                    .help("사진 편집 (Return)")
                    Button {
                        browser.openPhoto(url, in: .cutout)
                    } label: {
                        Label("오려내기", systemImage: AppTab.cutout.systemImage)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(DarkButtonStyle())
                }
                .font(.system(size: 12))
                .padding(10)
                .background(Theme.panel.opacity(0.92))
                Spacer()
            }
        }
        .background { keyboard }
        .task(id: url) {
            image = nil
            failed = false
            let target = url
            image = await Task.detached(priority: .userInitiated) {
                ImageLoader.thumbnail(for: target, maxPixelSize: 2400)
            }.value
            failed = image == nil
        }
    }

    private var index: Int? {
        browser.photos.firstIndex(of: url)
    }

    private func sideButton(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 64)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .opacity(enabled ? 0.85 : 0)
        .disabled(!enabled)
    }

    private var keyboard: some View {
        ZStack {
            Button("") { browser.moveSelection(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { browser.moveSelection(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { browser.closePreview() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("") { browser.closePreview() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { browser.openPhoto(url, in: .editor) }
                .keyboardShortcut(.return, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

struct ThumbnailView: View {
    let url: URL
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.05))
            }
        }
        .task(id: url) {
            if let cached = ThumbnailLoader.shared.cachedThumbnail(for: url) {
                image = cached
                return
            }
            image = await ThumbnailLoader.shared.thumbnail(for: url)
            failed = image == nil
        }
    }
}

// MARK: - 아래 상태 막대

private struct ViewerStatusBar: View {
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 150

    var body: some View {
        HStack(spacing: 12) {
            Text("폴더 \(browser.subfolders.count)개 · 사진 \(browser.photos.count)장")
                .monospacedDigit()
            if let selected = browser.selectedPhoto {
                Text("· \(selected.lastPathComponent)")
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let info = browser.fileInfo[selected] {
                    Text("· \(info.modified.formatted(date: .abbreviated, time: .shortened))")
                        .lineLimit(1)
                    Text("· \(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file))")
                        .lineLimit(1)
                }
            }

            Spacer()

            if let folder = browser.currentFolder {
                Button {
                    browser.toggleFavorite(folder)
                } label: {
                    Image(systemName: browser.isFavorite(folder) ? "star.fill" : "star")
                        .foregroundStyle(browser.isFavorite(folder) ? Color.yellow : Theme.text)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(DarkButtonStyle())
                .help(browser.isFavorite(folder) ? "즐겨찾기에서 제거" : "즐겨찾기에 추가")
            }
            Button {
                browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(DarkButtonStyle())
            .help("새로고침 (⌘R)")
            .keyboardShortcut("r", modifiers: .command)

            Image(systemName: "square.grid.3x3").font(.system(size: 10))
            Slider(value: $thumbnailSize, in: 80...320)
                .controlSize(.small)
                .frame(width: 120)
                .help("썸네일 크기")
            Image(systemName: "square.grid.2x2").font(.system(size: 12))
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.panel)
    }
}
