import CoreGraphics
import Foundation
import PSXCore
import UniformTypeIdentifiers

/// 사진 한 장의 편집 상태 (현재 이미지, 실행 취소 기록, 자르기 영역)
@MainActor
final class PhotoEditor: ObservableObject {
    enum Mode {
        case view
        case crop
    }

    let sourceURL: URL

    @Published private(set) var image: CGImage?
    @Published private(set) var loadError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var busyMessage = ""
    @Published var errorMessage: String?

    @Published private(set) var mode: Mode = .view
    /// 자르기 영역 (픽셀 단위, 왼쪽 위 원점)
    @Published var cropRect: CGRect = .zero

    @Published private var undoStack: [CGImage] = []
    @Published private var redoStack: [CGImage] = []
    /// 마지막으로 저장(또는 불러온) 상태의 이미지
    @Published private var savedImage: CGImage?

    private let historyLimit = 30
    private var isLoading = false

    init(url: URL) {
        sourceURL = url
    }

    var canUndo: Bool { !undoStack.isEmpty && !isBusy }
    var canRedo: Bool { !redoStack.isEmpty && !isBusy }
    var isModified: Bool {
        guard let image else { return false }
        return image !== savedImage
    }
    var canEdit: Bool { image != nil && !isBusy && mode == .view }
    /// 마지막으로 저장(또는 불러온) 상태 — "원본 비교"에 사용
    var originalImage: CGImage? { savedImage }
    var hasTransparency: Bool { image?.hasAlpha ?? false }

    /// 원본 파일 형식으로 덮어쓸 수 있는지 (RAW 등은 불가)
    var canOverwriteOriginal: Bool {
        ImageExporter.canWrite(fileExtension: sourceURL.pathExtension)
    }

    /// 덮어쓰면 투명한 배경이 흰색으로 바뀌는지
    var overwriteLosesTransparency: Bool {
        guard let image, image.hasAlpha,
              let type = UTType(filenameExtension: sourceURL.pathExtension) else { return false }
        return !ImageExporter.supportsTransparency(type)
    }

    // MARK: 불러오기

    func load() async {
        guard image == nil, loadError == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let url = sourceURL
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try ImageLoader.loadFullImage(url)
            }.value
            image = loaded
            savedImage = loaded
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: 편집 동작

    func rotate(clockwise: Bool) {
        perform("회전하는 중…") { try ImageOps.rotate($0, clockwise: clockwise) }
    }

    func flip(horizontal: Bool) {
        perform("뒤집는 중…") { try ImageOps.flip($0, horizontal: horizontal) }
    }

    func resize(width: Int, height: Int) {
        perform("크기 조절 중…") { try ImageOps.resize($0, width: width, height: height) }
    }

    func removeBackground() {
        perform("배경 제거 중…") { try ImageOps.removeBackground($0) }
    }

    /// 투명한 부분을 지정한 색으로 채웁니다.
    func fillBackground(_ color: CGColor) {
        perform("배경 채우는 중…") { try ImageOps.flatten($0, background: color) }
    }

    /// 마지막으로 저장한 상태로 되돌립니다. (실행 취소 가능)
    func revertToSaved() {
        guard !isBusy, let saved = savedImage, let current = image, current !== saved else { return }
        undoStack.append(current)
        redoStack.removeAll()
        image = saved
    }

    // MARK: 자르기

    func beginCrop(aspect: CGFloat?) {
        guard canEdit else { return }
        resetCropRect(aspect: aspect)
        mode = .crop
    }

    /// 주어진 비율로 가능한 가장 큰 영역을 가운데에 잡습니다.
    func resetCropRect(aspect: CGFloat?) {
        guard let image else { return }
        let size = image.pixelSize
        guard let aspect, aspect > 0 else {
            cropRect = CGRect(origin: .zero, size: size)
            return
        }
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        cropRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                          width: width, height: height)
    }

    func applyCrop() {
        let rect = cropRect
        mode = .view
        guard rect.width >= 1, rect.height >= 1 else { return }
        perform("자르는 중…") { try ImageOps.crop($0, to: rect) }
    }

    func cancelCrop() {
        mode = .view
    }

    // MARK: 실행 취소

    func undo() {
        guard canUndo, let current = image, let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        image = previous
    }

    func redo() {
        guard canRedo, let current = image, let next = redoStack.popLast() else { return }
        undoStack.append(current)
        image = next
    }

    // MARK: 저장

    /// 성공하면 true
    func save(to url: URL) async -> Bool {
        guard let image, !isBusy else { return false }
        let source = sourceURL
        isBusy = true
        busyMessage = "저장하는 중…"
        defer { isBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try ImageExporter.write(image, to: url, metadataFrom: source)
            }.value
            savedImage = image
            return true
        } catch {
            errorMessage = "저장하지 못했습니다.\n\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 내부

    /// 무거운 작업은 백그라운드에서 실행하고, 결과를 실행 취소 기록에 넣습니다.
    private func perform(_ message: String, _ operation: @escaping @Sendable (CGImage) throws -> CGImage) {
        guard let current = image, !isBusy else { return }
        isBusy = true
        busyMessage = message
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try operation(current)
                }.value
                undoStack.append(current)
                if undoStack.count > historyLimit { undoStack.removeFirst() }
                redoStack.removeAll()
                image = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, fourThree, threeFour, threeTwo, twoThree, sixteenNine, nineSixteen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "자유"
        case .original: return "원본 비율"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .threeFour: return "3:4"
        case .threeTwo: return "3:2"
        case .twoThree: return "2:3"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        }
    }

    /// 너비 / 높이. 자유 비율이면 nil
    func ratio(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: return nil
        case .original: return imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeFour: return 3.0 / 4.0
        case .threeTwo: return 3.0 / 2.0
        case .twoThree: return 2.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}
