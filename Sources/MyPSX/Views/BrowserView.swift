import SwiftUI

/// 폴더 안의 하위 폴더와 사진을 썸네일 격자로 보여줍니다.
struct BrowserView: View {
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 150

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                browser.requestNavigation { browser.goUp() }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!browser.canGoUp)
            .help("상위 폴더")
            .keyboardShortcut(.upArrow, modifiers: .command)

            VStack(alignment: .leading, spacing: 1) {
                Text(browser.currentFolder?.lastPathComponent ?? "폴더 없음")
                    .font(.headline)
                Text(browser.currentFolder?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if browser.isLoading {
                ProgressView().controlSize(.small)
            }
            Text("사진 \(browser.photos.count)장")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
            Slider(value: $thumbnailSize, in: 80...320)
                .frame(width: 110)
                .help("썸네일 크기")
            Image(systemName: "photo").font(.body).foregroundStyle(.secondary)

            if let folder = browser.currentFolder {
                Button {
                    browser.toggleFavorite(folder)
                } label: {
                    Image(systemName: browser.isFavorite(folder) ? "star.fill" : "star")
                }
                .help(browser.isFavorite(folder) ? "즐겨찾기에서 제거" : "즐겨찾기에 추가")
            }

            Button {
                browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("새로고침")
            .keyboardShortcut("r", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if browser.currentFolder == nil {
            ContentUnavailableView {
                Label("폴더를 선택하세요", systemImage: "folder")
            } description: {
                Text("사진이 들어 있는 폴더를 열면 여기에 표시됩니다.")
            } actions: {
                Button("폴더 열기…") { browser.chooseFolder() }
            }
        } else if browser.subfolders.isEmpty && browser.photos.isEmpty {
            if browser.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("사진이 없습니다", systemImage: "photo.on.rectangle",
                                       description: Text("이 폴더에는 사진이나 하위 폴더가 없습니다."))
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        let size = CGFloat(thumbnailSize)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 12), spacing: 8)], spacing: 8) {
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
                            Button("편집") { browser.openPhoto(photo) }
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

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor.opacity(0.8))
                .padding(size * 0.2)
                .frame(width: size, height: size)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: size)
        }
        .padding(6)
        .contentShape(Rectangle())
        .help(url.lastPathComponent)
    }
}

private struct PhotoTile: View {
    let url: URL
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(url: url)
                .frame(width: size, height: size)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: size)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        )
        .contentShape(Rectangle())
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
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
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
