import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var browser: FolderBrowser

    var body: some View {
        List {
            Section("위치") {
                ForEach(browser.standardLocations, id: \.self) { url in
                    row(url, systemImage: icon(for: url))
                }
            }
            Section("즐겨찾기") {
                if browser.favorites.isEmpty {
                    Text("폴더 화면의 ☆ 버튼으로 추가하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(browser.favorites, id: \.self) { url in
                    row(url, systemImage: "star.fill")
                        .contextMenu {
                            Button("즐겨찾기에서 제거") { browser.toggleFavorite(url) }
                            Button("Finder에서 보기") { browser.revealInFinder(url) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                browser.chooseFolder()
            } label: {
                Label("폴더 열기…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(10)
        }
    }

    private func row(_ url: URL, systemImage: String) -> some View {
        let isCurrent = browser.currentFolder == url.normalizedFolder
        return Button {
            browser.requestNavigation { browser.open(folder: url) }
        } label: {
            Label(url.lastPathComponent, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isCurrent ? Color.accentColor.opacity(0.2) : .clear)
        )
        .help(url.path)
    }

    private func icon(for url: URL) -> String {
        let fileManager = FileManager.default
        func standard(_ directory: FileManager.SearchPathDirectory) -> URL? {
            fileManager.urls(for: directory, in: .userDomainMask).first?.normalizedFolder
        }
        let url = url.normalizedFolder
        if url == fileManager.homeDirectoryForCurrentUser.normalizedFolder { return "house" }
        if url == standard(.picturesDirectory) { return "photo.on.rectangle" }
        if url == standard(.desktopDirectory) { return "menubar.dock.rectangle" }
        if url == standard(.downloadsDirectory) { return "arrow.down.circle" }
        return "folder"
    }
}
