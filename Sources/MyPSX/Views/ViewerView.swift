import SwiftUI

/// 뷰어 탭: 왼쪽 폴더 트리 + 가운데 썸네일 + 아래 상태 막대
struct ViewerView: View {
    var body: some View {
        HStack(spacing: 0) {
            FolderTreeView()
                .frame(width: 240)
            PanelDivider()
            VStack(spacing: 0) {
                PathBar()
                PanelDivider(vertical: false)
                ThumbnailGrid()
                PanelDivider(vertical: false)
                ViewerStatusBar()
            }
        }
    }
}

// MARK: - 폴더 트리

private struct FolderTreeView: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PanelHeader(title: "즐겨찾기")
                    if browser.favorites.isEmpty {
                        Text("폴더를 연 뒤 아래 ☆ 버튼으로 추가하세요")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)
                    }
                    ForEach(browser.favorites, id: \.self) { url in
                        FolderTreeRow(url: url, depth: 0, icon: "star.fill", iconColor: .yellow)
                    }

                    PanelHeader(title: "위치")
                    ForEach(browser.standardLocations, id: \.self) { url in
                        FolderTreeRow(url: url, depth: 0, icon: icon(for: url), iconColor: Theme.folder)
                    }
                }
                .padding(.bottom, 8)
            }

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
        .background(Theme.panel)
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
        if url == standard(.downloadsDirectory) { return "arrow.down.circle.fill" }
        return "folder.fill"
    }
}

/// 트리의 한 줄. 화살표를 누르면 하위 폴더를 불러와 펼칩니다.
private struct FolderTreeRow: View {
    @EnvironmentObject private var browser: FolderBrowser
    let url: URL
    let depth: Int
    var icon = "folder.fill"
    var iconColor = Theme.folder

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
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, CGFloat(depth) * 14 + 6)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(rowBackground)
            .contentShape(Rectangle())
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
                    FolderTreeRow(url: child, depth: depth + 1)
                }
            }
        }
    }

    private var isCurrent: Bool {
        browser.currentFolder == url.normalizedFolder
    }

    private var rowBackground: Color {
        if isCurrent { return Theme.accent.opacity(0.45) }
        return hovering ? Theme.hover : .clear
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() }
        guard expanded, children == nil else { return }
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
        HStack(spacing: 10) {
            Button {
                browser.requestNavigation { browser.goUp() }
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(DarkButtonStyle())
            .disabled(!browser.canGoUp)
            .help("상위 폴더 (⌘↑)")
            .keyboardShortcut(.upArrow, modifiers: .command)

            Image(systemName: "folder.fill")
                .foregroundStyle(Theme.folder)
            Text(browser.currentFolder?.lastPathComponent ?? "폴더 없음")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(browser.currentFolder?.path ?? "")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            if browser.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.panel)
    }
}

// MARK: - 썸네일 격자

private struct ThumbnailGrid: View {
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 150

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
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 16), spacing: 6)], spacing: 6) {
                ForEach(browser.subfolders, id: \.self) { folder in
                    FolderTile(url: folder, size: size)
                        .onTapGesture(count: 2) {
                            browser.open(folder: folder)
                        }
                        .contextMenu {
                            Button("열기") { browser.open(folder: folder) }
                            Button("Finder에서 보기") { browser.revealInFinder(folder) }
                        }
                }
                ForEach(browser.photos, id: \.self) { photo in
                    PhotoTile(url: photo, size: size, isSelected: browser.selectedPhoto == photo)
                        .onTapGesture(count: 2) {
                            browser.openPhoto(photo)
                        }
                        .onTapGesture {
                            browser.selectedPhoto = photo
                        }
                        .contextMenu {
                            Button("사진 편집") { browser.openPhoto(photo, in: .editor) }
                            Button("누끼 (배경 제거)") { browser.openPhoto(photo, in: .cutout) }
                            Divider()
                            Button("Finder에서 보기") { browser.revealInFinder(photo) }
                        }
                }
            }
            .padding(12)
        }
        .id(browser.currentFolder)
        .background {
            // 선택된 사진을 Return 키로 열기
            Button("") {
                if let selected = browser.selectedPhoto { browser.openPhoto(selected) }
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
        }
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
                    .lineLimit(1)
                    .truncationMode(.middle)
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
