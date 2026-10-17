import AppKit
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
    /// 방금 끝난 작업이 오래 걸렸으면 걸린 시간 (예: "걸린 시간 34초")
    @Published private(set) var lastTiming: String?
    @Published var errorMessage: String?

    @Published private(set) var mode: Mode = .view
    /// 밝기·대비·채도를 움직이는 동안 보여줄 미리보기 (작게 줄인 이미지)
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var isAdjusting = false
    /// 자르기 영역 (픽셀 단위, 왼쪽 위 원점)
    @Published var cropRect: CGRect = .zero

    @Published private var undoStack: [CGImage] = []
    @Published private var redoStack: [CGImage] = []
    /// 마지막으로 저장(또는 불러온) 상태의 이미지
    @Published private var savedImage: CGImage?

    private let historyLimit = 30
    private var isLoading = false
    private var previewBase: CGImage?
    private var previewTask: Task<Void, Never>?

    init(url: URL) {
        sourceURL = url
    }

    var canUndo: Bool { !undoStack.isEmpty && !isBusy }
    var canRedo: Bool { !redoStack.isEmpty && !isBusy }
    var isModified: Bool {
        guard let image else { return false }
        return image !== savedImage
    }
    var canEdit: Bool { image != nil && !isBusy && mode == .view && !isAdjusting }
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

    /// macOS 내장 기능으로 배경 제거(1초 안팎). 기본은 흰색 배경, transparent면 투명 배경.
    /// largestOnly면 가장 큰 물체(상품)만 남기고 아이콘·글자 같은 작은 물체는 지웁니다.
    func removeBackground(transparent: Bool = false, largestOnly: Bool = false) {
        perform("배경 제거 중…") { image in
            let cutout = try ImageOps.removeBackground(image, largestOnly: largestOnly)
            return try transparent ? cutout : ImageOps.flatten(cutout)
        }
    }

    // MARK: 밝기 / 대비 / 채도

    /// 슬라이더를 움직일 때마다 작은 이미지로 빠르게 미리보기를 만듭니다.
    func updateAdjustmentPreview(_ adjustments: ImageAdjustments) {
        guard let image, !isBusy else { return }
        guard !adjustments.isIdentity else {
            endAdjustmentPreview()
            return
        }
        isAdjusting = true
        if previewBase == nil {
            previewBase = (try? ImageOps.downscaled(image, maxPixelSize: 1600)) ?? image
        }
        guard let base = previewBase else { return }
        previewTask?.cancel()
        previewTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                try? ImageOps.adjust(base, adjustments)
            }.value
            guard !Task.isCancelled, isAdjusting else { return }
            previewImage = result
        }
    }

    func endAdjustmentPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewImage = nil
        previewBase = nil
        isAdjusting = false
    }

    /// 원본 크기 그대로 조정을 적용합니다. (실행 취소 가능)
    func applyAdjustments(_ adjustments: ImageAdjustments) {
        endAdjustmentPreview()
        guard !adjustments.isIdentity else { return }
        perform("조정 적용 중…") { try ImageOps.adjust($0, adjustments) }
    }

    // MARK: AI (GPT)

    /// 글로 쓴 지시대로 AI가 사진을 수정합니다.
    func aiEdit(_ ai: any AIImageEditor, prompt: String) {
        perform("AI가 사진을 수정하는 중… (1~2분 걸릴 수 있습니다)") {
            try await ai.edit($0, prompt: prompt, transparentBackground: false)
        }
    }

    /// GPT 빠른 배경 제거: macOS가 물체를 찾고, GPT는 어느 것이 상품인지만 고르고, macOS가 오립니다.
    /// 사진을 새로 그리지 않아 빠르고 상품은 원본 그대로입니다.
    func quickAIRemoveBackground(_ picker: any AIProductPicker, transparent: Bool) {
        perform("GPT가 상품을 고르는 중…") { image in
            try await ProductCutout.run(image, picker: picker, transparent: transparent)
        }
    }

    /// AI로 배경을 정리합니다. 기본은 흰색 배경, transparent면 투명 배경.
    /// 투명 배경을 직접 못 만드는 AI(Codex)는 흰 배경으로 정리한 뒤 macOS 기능으로 배경을 지웁니다.
    func aiRemoveBackground(_ ai: any AIImageEditor, transparent: Bool) {
        perform("AI가 배경을 정리하는 중… (1~2분 걸릴 수 있습니다)") { image in
            if transparent && ai.supportsTransparentBackground {
                return try await ai.edit(image, prompt: AIPrompts.transparentBackground, transparentBackground: true)
            }
            let white = try await ai.edit(image, prompt: AIPrompts.whiteBackground, transparentBackground: false)
            guard transparent else {
                return try white.hasAlpha ? ImageOps.flatten(white) : white
            }
            return try ImageOps.removeBackground(white)
        }
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

    /// 자르기 선택 영역만 잘라 낸 이미지. 편집 중인 사진은 그대로 둡니다.
    func selectionImage() throws -> CGImage {
        guard let image, cropRect.width >= 1, cropRect.height >= 1 else { throw ImageError.renderFailed }
        return try ImageOps.crop(image, to: cropRect)
    }

    /// 선택 영역만 새 파일로 저장합니다. (원본 사진의 메타데이터를 이어받음)
    func saveSelection(to url: URL) async -> Bool {
        let source = sourceURL
        do {
            let selection = try selectionImage()
            try await Task.detached(priority: .userInitiated) {
                try ImageExporter.write(selection, to: url, metadataFrom: source)
            }.value
            return true
        } catch {
            errorMessage = "선택 영역을 저장하지 못했습니다.\n\(error.localizedDescription)"
            return false
        }
    }

    /// 선택 영역을 클립보드에 복사합니다. (PNG + TIFF)
    @discardableResult
    func copySelectionToClipboard() -> Bool {
        do {
            let selection = try selectionImage()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let png = try ImageEncoding.pngData(selection)
            pasteboard.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(cgImage: selection).tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            return true
        } catch {
            errorMessage = "클립보드에 복사하지 못했습니다.\n\(error.localizedDescription)"
            return false
        }
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
    private func perform(_ message: String, _ operation: @escaping @Sendable (CGImage) async throws -> CGImage) {
        guard let current = image, !isBusy else { return }
        isBusy = true
        busyMessage = message
        let started = Date()
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await operation(current)
                }.value
                let seconds = Date().timeIntervalSince(started)
                lastTiming = seconds >= 2 ? "걸린 시간 \(Int(seconds.rounded()))초" : nil
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
