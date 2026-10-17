import AppKit
import Foundation
import SwiftUI
import PSXCore

/// 현재 열린 폴더와 그 안의 하위 폴더 / 사진 목록을 관리합니다.
@MainActor
final class FolderBrowser: ObservableObject {
    @Published private(set) var currentFolder: URL?
    @Published private(set) var subfolders: [URL] = []
    @Published private(set) var photos: [URL] = []
    @Published private(set) var favorites: [URL] = []
    @Published private(set) var isLoading = false

    @Published var selectedPhoto: URL?
    /// 편집 중인 사진
    @Published private(set) var openedPhoto: URL?
    /// 편집 중인 사진의 편집 상태 (사진 편집 / 누끼 탭이 함께 사용)
    @Published private(set) var editor: PhotoEditor?
    /// 상단 탭
    @Published var tab: AppTab = .viewer

    /// 편집 화면에 저장하지 않은 변경사항이 있는지 (편집 화면이 갱신합니다)
    @Published var hasUnsavedEdits = false
    /// 저장하지 않은 변경사항 때문에 확인을 기다리는 이동 동작
    @Published var pendingNavigation: PendingNavigation?
    @Published var errorMessage: String?

    struct PendingNavigation {
        let action: () -> Void
    }

    let standardLocations: [URL]

    private var loadGeneration = 0
    private let favoritesKey = "favoriteFolders"
    private let lastFolderKey = "lastFolder"

    /// - Parameter launchArguments: 실행 인자. 폴더나 사진 경로가 있으면 바로 엽니다.
    init(launchArguments: [String] = []) {
        let fileManager = FileManager.default
        var locations = [fileManager.homeDirectoryForCurrentUser]
        for directory in [FileManager.SearchPathDirectory.picturesDirectory, .desktopDirectory, .downloadsDirectory] {
            if let url = fileManager.urls(for: directory, in: .userDomainMask).first {
                locations.append(url)
            }
        }
        standardLocations = locations

        favorites = (UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).normalizedFolder }

        if openLaunchTarget(from: launchArguments) {
            return
        }
        if let lastPath = UserDefaults.standard.string(forKey: lastFolderKey),
           fileManager.fileExists(atPath: lastPath) {
            open(folder: URL(fileURLWithPath: lastPath, isDirectory: true))
        } else if let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first {
            open(folder: pictures)
        }
    }

    /// 실행 인자 중 존재하는 폴더/사진 경로를 엽니다. 열었으면 true
    private func openLaunchTarget(from arguments: [String]) -> Bool {
        let fileManager = FileManager.default
        for argument in arguments.dropFirst() where !argument.hasPrefix("-") {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: argument, isDirectory: &isDirectory) else { continue }
            let url = URL(fileURLWithPath: argument).standardizedFileURL
            if isDirectory.boolValue {
                open(folder: url)
                return true
            }
            if ImageLoader.isSupportedImage(url) {
                let folder = url.deletingLastPathComponent().normalizedFolder
                open(folder: folder)
                // 폴더 목록의 URL과 같은 형태로 맞춥니다.
                openPhoto(folder.appendingPathComponent(url.lastPathComponent))
                return true
            }
        }
        return false
    }

    // MARK: 폴더 이동

    func open(folder: URL) {
        currentFolder = folder.normalizedFolder
        closePhoto()
        tab = .viewer
        selectedPhoto = nil
        subfolders = []
        photos = []
        UserDefaults.standard.set(folder.path, forKey: lastFolderKey)
        reload()
    }

    var canGoUp: Bool {
        guard let currentFolder else { return false }
        return currentFolder.path != "/"
    }

    func goUp() {
        guard let currentFolder, canGoUp else { return }
        open(folder: currentFolder.deletingLastPathComponent())
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "열기"
        panel.directoryURL = currentFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        requestNavigation { self.open(folder: url) }
    }

    func reload() {
        guard let folder = currentFolder else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FolderBrowser.scan(folder) }
            }.value
            // 그 사이 다른 폴더로 이동했다면 결과를 버립니다.
            guard generation == loadGeneration else { return }
            isLoading = false
            switch result {
            case .success(let contents):
                subfolders = contents.folders
                photos = contents.photos
                // /var → /private/var 처럼 같은 파일이 다른 경로로 보일 수 있어 이름으로 맞춥니다.
                openedPhoto = matching(openedPhoto, in: contents.photos)
                selectedPhoto = matching(selectedPhoto, in: contents.photos)
                if openedPhoto == nil { closePhoto() }
            case .failure(let error):
                subfolders = []
                photos = []
                errorMessage = "폴더를 읽을 수 없습니다.\n\(error.localizedDescription)"
            }
        }
    }

    /// 목록에서 같은 파일을 찾습니다. 없으면 nil
    private func matching(_ url: URL?, in photos: [URL]) -> URL? {
        guard let url else { return nil }
        if photos.contains(url) { return url }
        return photos.first { $0.lastPathComponent == url.lastPathComponent }
    }

    struct FolderContents {
        var folders: [URL]
        var photos: [URL]
    }

    /// 폴더 트리용: 하위 폴더 목록
    nonisolated static func subfolders(of folder: URL) -> [URL] {
        (try? scan(folder).folders) ?? []
    }

    nonisolated static func scan(_ folder: URL) throws -> FolderContents {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])

        var folders: [URL] = []
        var photos: [URL] = []
        for item in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true && values?.isPackage != true {
                folders.append(item)
            } else if ImageLoader.isSupportedImage(item) {
                photos.append(item)
            }
        }
        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return FolderContents(folders: folders.sorted(by: byName), photos: photos.sorted(by: byName))
    }

    // MARK: 사진 열기

    var openedPhotoIndex: Int? {
        guard let openedPhoto else { return nil }
        return photos.firstIndex(of: openedPhoto)
    }

    /// 사진을 편집기로 엽니다. 이미 열려 있는 사진이면 편집 상태를 그대로 둡니다.
    func openPhoto(_ url: URL, in tab: AppTab = .editor) {
        selectedPhoto = url
        if openedPhoto != url || editor == nil {
            openedPhoto = url
            let editor = PhotoEditor(url: url)
            self.editor = editor
            hasUnsavedEdits = false
            Task { await editor.load() }
        }
        self.tab = tab
    }

    func closePhoto() {
        openedPhoto = nil
        editor = nil
        hasUnsavedEdits = false
    }

    /// 탭 전환. 편집 탭으로 갈 때 열린 사진이 없으면 선택된 사진(없으면 첫 사진)을 엽니다.
    func switchTab(_ tab: AppTab) {
        if tab != .viewer, editor == nil, let photo = selectedPhoto ?? photos.first {
            openPhoto(photo, in: tab)
        } else {
            self.tab = tab
        }
    }

    func canMove(by offset: Int) -> Bool {
        guard let index = openedPhotoIndex else { return false }
        return photos.indices.contains(index + offset)
    }

    func move(by offset: Int) {
        guard let index = openedPhotoIndex, photos.indices.contains(index + offset) else { return }
        openPhoto(photos[index + offset], in: tab == .viewer ? .editor : tab)
    }

    /// 저장하지 않은 편집이 있으면 사용자에게 먼저 확인합니다.
    func requestNavigation(_ action: @escaping () -> Void) {
        if hasUnsavedEdits {
            pendingNavigation = PendingNavigation(action: action)
        } else {
            action()
        }
    }

    // MARK: 즐겨찾기

    func isFavorite(_ url: URL) -> Bool {
        favorites.contains(url.normalizedFolder)
    }

    func toggleFavorite(_ url: URL) {
        let url = url.normalizedFolder
        if let index = favorites.firstIndex(of: url) {
            favorites.remove(at: index)
        } else {
            favorites.append(url)
        }
        UserDefaults.standard.set(favorites.map(\.path), forKey: favoritesKey)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case viewer, editor, cutout

    var id: Self { self }

    var title: String {
        switch self {
        case .viewer: return "뷰어"
        case .editor: return "사진 편집"
        case .cutout: return "누끼"
        }
    }

    var systemImage: String {
        switch self {
        case .viewer: return "photo.on.rectangle.angled"
        case .editor: return "slider.horizontal.3"
        case .cutout: return "scissors"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .viewer: return "1"
        case .editor: return "2"
        case .cutout: return "3"
        }
    }
}

extension URL {
    /// 끝의 "/" 유무 등과 상관없이 같은 폴더면 같은 값이 되도록 정규화합니다.
    var normalizedFolder: URL {
        URL(fileURLWithPath: standardizedFileURL.path, isDirectory: true)
    }
}
