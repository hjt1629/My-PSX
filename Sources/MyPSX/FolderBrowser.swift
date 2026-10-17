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
    /// 뷰어에서 크게 보고 있는 사진 (nil이면 썸네일 목록)
    @Published private(set) var previewPhoto: URL?

    /// 뒤로 / 앞으로 이동 기록
    @Published private(set) var backStack: [URL] = []
    @Published private(set) var forwardStack: [URL] = []

    /// 사진 정렬 기준
    @Published var sort: PhotoSort {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: sortKey)
            applySort()
        }
    }
    @Published var sortAscending: Bool {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: sortAscendingKey)
            applySort()
        }
    }
    /// 사진 파일 정보 (정렬 / 상태 막대용)
    private(set) var fileInfo: [URL: FileInfo] = [:]
    /// 편집 중인 사진
    @Published private(set) var openedPhoto: URL?
    /// 편집 중인 사진의 편집 상태 (사진 편집 / 오려내기 탭이 함께 사용)
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
    /// 연결된 디스크 (Macintosh HD, 외장 디스크 등)
    let volumes: [URL]

    private var loadGeneration = 0
    private let favoritesKey = "favoriteFolders"
    private let lastFolderKey = "lastFolder"
    private let sortKey = "photoSort"
    private let sortAscendingKey = "photoSortAscending"

    /// - Parameter launchArguments: 실행 인자. 폴더나 사진 경로가 있으면 바로 엽니다.
    init(launchArguments: [String] = []) {
        let fileManager = FileManager.default
        var locations = [fileManager.homeDirectoryForCurrentUser]
        for directory in [FileManager.SearchPathDirectory.picturesDirectory, .desktopDirectory,
                          .documentDirectory, .downloadsDirectory] {
            if let url = fileManager.urls(for: directory, in: .userDomainMask).first {
                locations.append(url)
            }
        }
        standardLocations = locations
        volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                options: [.skipHiddenVolumes]) ?? []

        let defaults = UserDefaults.standard
        sort = defaults.string(forKey: "photoSort").flatMap(PhotoSort.init(rawValue:)) ?? .name
        sortAscending = defaults.object(forKey: "photoSortAscending") as? Bool ?? true

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
        navigate(to: folder, recordHistory: true)
    }

    private func navigate(to folder: URL, recordHistory: Bool) {
        let target = folder.normalizedFolder
        if recordHistory, let current = currentFolder, current != target {
            backStack.append(current)
            forwardStack.removeAll()
        }
        currentFolder = target
        // 편집 중인 사진은 다른 폴더로 가도 그대로 둡니다. (PhotoScape X와 같은 방식)
        selectedPhoto = nil
        previewPhoto = nil
        subfolders = []
        photos = []
        fileInfo = [:]
        UserDefaults.standard.set(target.path, forKey: lastFolderKey)
        reload()
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let currentFolder { forwardStack.append(currentFolder) }
        navigate(to: previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let currentFolder { backStack.append(currentFolder) }
        navigate(to: next, recordHistory: false)
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
                fileInfo = contents.info
                photos = FolderBrowser.sorted(contents.photos, info: contents.info, by: sort, ascending: sortAscending)
                // /var → /private/var 처럼 같은 파일이 다른 경로로 보일 수 있어 실제 경로로 맞춥니다.
                if let match = matching(openedPhoto, in: photos) { openedPhoto = match }
                selectedPhoto = matching(selectedPhoto, in: photos)
                previewPhoto = matching(previewPhoto, in: photos)
            case .failure(let error):
                subfolders = []
                photos = []
                fileInfo = [:]
                errorMessage = "폴더를 읽을 수 없습니다.\n\(error.localizedDescription)"
            }
        }
    }

    /// 목록에서 같은 파일을 찾습니다. 없으면 nil
    private func matching(_ url: URL?, in photos: [URL]) -> URL? {
        guard let url else { return nil }
        if photos.contains(url) { return url }
        let path = url.resolvedPath
        return photos.first { $0.resolvedPath == path }
    }

    struct FolderContents {
        var folders: [URL]
        var photos: [URL]
        var info: [URL: FileInfo] = [:]
    }

    struct FileInfo: Equatable {
        var modified: Date
        var size: Int
    }

    private func applySort() {
        photos = FolderBrowser.sorted(photos, info: fileInfo, by: sort, ascending: sortAscending)
    }

    /// 정렬. 기준 값이 같으면 이름순으로 정렬합니다.
    nonisolated static func sorted(_ photos: [URL], info: [URL: FileInfo],
                                   by sort: PhotoSort, ascending: Bool) -> [URL] {
        func nameOrder(_ a: URL, _ b: URL) -> ComparisonResult {
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
        }
        func order(_ a: URL, _ b: URL) -> ComparisonResult {
            switch sort {
            case .name:
                return nameOrder(a, b)
            case .date:
                let da = info[a]?.modified ?? .distantPast, db = info[b]?.modified ?? .distantPast
                return da == db ? nameOrder(a, b) : (da < db ? .orderedAscending : .orderedDescending)
            case .size:
                let sa = info[a]?.size ?? 0, sb = info[b]?.size ?? 0
                return sa == sb ? nameOrder(a, b) : (sa < sb ? .orderedAscending : .orderedDescending)
            case .type:
                let ta = a.pathExtension.lowercased(), tb = b.pathExtension.lowercased()
                return ta == tb ? nameOrder(a, b) : (ta < tb ? .orderedAscending : .orderedDescending)
            }
        }
        return photos.sorted { a, b in
            let result = order(a, b)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    /// 폴더 트리용: 하위 폴더 목록
    nonisolated static func subfolders(of folder: URL) -> [URL] {
        (try? scan(folder).folders) ?? []
    }

    nonisolated static func scan(_ folder: URL) throws -> FolderContents {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])

        var folders: [URL] = []
        var photos: [URL] = []
        var info: [URL: FileInfo] = [:]
        for item in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true && values?.isPackage != true {
                folders.append(item)
            } else if ImageLoader.isSupportedImage(item) {
                photos.append(item)
                info[item] = FileInfo(modified: values?.contentModificationDate ?? .distantPast,
                                      size: values?.fileSize ?? 0)
            }
        }
        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return FolderContents(folders: folders.sorted(by: byName), photos: photos.sorted(by: byName), info: info)
    }

    // MARK: 선택 / 크게 보기

    /// 선택을 offset만큼 옮깁니다. 선택이 없으면 첫 사진을 고릅니다.
    func moveSelection(by offset: Int) {
        guard !photos.isEmpty else { return }
        let target: Int
        if let selectedPhoto, let index = photos.firstIndex(of: selectedPhoto) {
            target = min(max(index + offset, 0), photos.count - 1)
        } else {
            target = 0
        }
        selectedPhoto = photos[target]
        if previewPhoto != nil { previewPhoto = photos[target] }
    }

    func preview(_ url: URL) {
        selectedPhoto = url
        previewPhoto = url
    }

    func closePreview() {
        previewPhoto = nil
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

enum PhotoSort: String, CaseIterable, Identifiable {
    case name, date, size, type

    var id: Self { self }

    var title: String {
        switch self {
        case .name: return "이름"
        case .date: return "수정한 날짜"
        case .size: return "파일 크기"
        case .type: return "종류"
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case viewer, editor, cutout

    var id: Self { self }

    var title: String {
        switch self {
        case .viewer: return "사진 뷰어"
        case .editor: return "사진 편집"
        case .cutout: return "오려내기"
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

    /// 심볼릭 링크까지 풀어낸 경로 (/var → /private/var 등)
    var resolvedPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// self가 other와 같거나 other를 포함하는 상위 폴더인지
    func contains(_ other: URL) -> Bool {
        let base = resolvedPath, target = other.resolvedPath
        if base == target || base == "/" { return true }
        return target.hasPrefix(base + "/")
    }

    /// Finder와 같은 표시 이름 (사진, 데스크탑, Macintosh HD …)
    var displayName: String {
        FileManager.default.displayName(atPath: path)
    }
}
