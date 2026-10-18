import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import MyPSX
import PSXCore

final class AppFlowTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PSXTest-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder.appendingPathComponent("하위 폴더"),
                                        withIntermediateDirectories: true)
        try ImageExporter.write(makeImage(width: 40, height: 20), to: folder.appendingPathComponent("photo10.jpg"),
                                metadataFrom: nil)
        try ImageExporter.write(makeImage(width: 30, height: 30), to: folder.appendingPathComponent("photo2.png"),
                                metadataFrom: nil)
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("memo.txt"))
        try Data().write(to: folder.appendingPathComponent(".hidden.jpg"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: 폴더 탐색

    @MainActor
    func testScanListsSubfoldersAndPhotosInNaturalOrder() throws {
        let contents = try FolderBrowser.scan(folder)
        XCTAssertEqual(contents.folders.map(\.lastPathComponent), ["하위 폴더"])
        // 숨김 파일, 텍스트 파일 제외 / 숫자는 자연 정렬 (2 < 10)
        XCTAssertEqual(contents.photos.map(\.lastPathComponent), ["photo2.png", "photo10.jpg"])
    }

    @MainActor
    func testLaunchWithPhotoOpensFolderAndEditor() async throws {
        let photo = folder.appendingPathComponent("photo10.jpg")
        let browser = FolderBrowser(launchArguments: ["MyPSX", photo.path])
        try await waitUntil { !browser.isLoading && browser.photos.count == 2 }

        XCTAssertEqual(browser.currentFolder?.path, folder.standardizedFileURL.path)
        XCTAssertEqual(browser.openedPhoto?.lastPathComponent, "photo10.jpg")
        XCTAssertEqual(browser.openedPhotoIndex, 1)

        // 이전 / 다음 사진
        XCTAssertTrue(browser.canMove(by: -1))
        XCTAssertFalse(browser.canMove(by: 1))
        browser.move(by: -1)
        XCTAssertEqual(browser.openedPhoto?.lastPathComponent, "photo2.png")

        // 다른 폴더로 가도 편집 중인 사진은 그대로입니다. (그 폴더 목록에는 없음)
        let editor = try XCTUnwrap(browser.editor)
        browser.open(folder: folder.appendingPathComponent("하위 폴더"))
        try await waitUntil { !browser.isLoading }
        XCTAssertTrue(browser.editor === editor)
        XCTAssertEqual(browser.openedPhoto?.lastPathComponent, "photo2.png")
        XCTAssertNil(browser.openedPhotoIndex)
        XCTAssertFalse(browser.canMove(by: 1))

        browser.goUp()
        XCTAssertEqual(browser.currentFolder?.path, folder.standardizedFileURL.path)
        try await waitUntil { !browser.isLoading && browser.photos.count == 2 }
        XCTAssertEqual(browser.openedPhotoIndex, 0)
    }

    @MainActor
    func testTabsShareTheOpenEditor() async throws {
        let browser = FolderBrowser(launchArguments: ["MyPSX", folder.path])
        try await waitUntil { !browser.isLoading && browser.photos.count == 2 }
        XCTAssertEqual(browser.tab, .viewer)
        XCTAssertNil(browser.editor)

        // 사진 없이 편집 탭으로 가면 선택된 사진(없으면 첫 사진)을 엽니다.
        browser.switchTab(.editor)
        XCTAssertEqual(browser.tab, .editor)
        let editor = try XCTUnwrap(browser.editor)
        XCTAssertEqual(editor.sourceURL.lastPathComponent, "photo2.png")
        try await waitUntil { editor.image != nil }

        // 뷰어 / 오려내기 탭을 오가도 같은 편집 상태를 유지합니다.
        editor.rotate(clockwise: true)
        try await waitForIdle(editor)
        browser.switchTab(.viewer)
        browser.switchTab(.cutout)
        XCTAssertTrue(browser.editor === editor)
        XCTAssertTrue(editor.isModified)

        // 같은 사진을 다시 열어도 편집이 사라지지 않습니다.
        browser.openPhoto(editor.sourceURL, in: .cutout)
        XCTAssertTrue(browser.editor === editor)

        // 다른 사진을 열면 새 편집 상태가 되고, 지금 탭은 그대로입니다.
        browser.move(by: 1)
        XCTAssertFalse(browser.editor === editor)
        XCTAssertEqual(browser.editor?.sourceURL.lastPathComponent, "photo10.jpg")
        XCTAssertEqual(browser.tab, .cutout)

        // 다른 폴더를 열어도 편집기와 탭은 그대로입니다.
        let current = browser.editor
        browser.open(folder: folder.appendingPathComponent("하위 폴더"))
        XCTAssertTrue(browser.editor === current)
        XCTAssertEqual(browser.tab, .cutout)

        // 닫으면 편집기가 사라집니다.
        browser.closePhoto()
        XCTAssertNil(browser.editor)
        XCTAssertNil(browser.openedPhoto)
    }

    @MainActor
    func testBackForwardHistory() async throws {
        let browser = FolderBrowser(launchArguments: ["MyPSX", folder.path])
        let root = try XCTUnwrap(browser.currentFolder)
        let sub = folder.appendingPathComponent("하위 폴더")
        XCTAssertFalse(browser.canGoBack)

        browser.open(folder: sub)
        XCTAssertTrue(browser.canGoBack)
        XCTAssertFalse(browser.canGoForward)

        browser.goBack()
        XCTAssertEqual(browser.currentFolder, root)
        XCTAssertTrue(browser.canGoForward)

        browser.goForward()
        XCTAssertEqual(browser.currentFolder?.lastPathComponent, "하위 폴더")

        // 같은 폴더를 다시 열면 기록이 늘지 않습니다.
        let depth = browser.backStack.count
        browser.open(folder: sub)
        XCTAssertEqual(browser.backStack.count, depth)

        // 새로 이동하면 앞으로 기록은 지워집니다.
        browser.goBack()
        browser.goUp()
        XCTAssertFalse(browser.canGoForward)
    }

    @MainActor
    func testSelectionAndPreview() async throws {
        let browser = FolderBrowser(launchArguments: ["MyPSX", folder.path])
        try await waitUntil { !browser.isLoading && browser.photos.count == 2 }

        // 선택이 없을 때 방향키는 첫 사진을 고릅니다.
        browser.moveSelection(by: 1)
        XCTAssertEqual(browser.selectedPhoto?.lastPathComponent, "photo2.png")
        browser.moveSelection(by: 5)
        XCTAssertEqual(browser.selectedPhoto?.lastPathComponent, "photo10.jpg")
        browser.moveSelection(by: -5)
        XCTAssertEqual(browser.selectedPhoto?.lastPathComponent, "photo2.png")

        // 크게 보기 중에는 넘기면 크게 보는 사진도 바뀝니다.
        browser.preview(try XCTUnwrap(browser.selectedPhoto))
        browser.moveSelection(by: 1)
        XCTAssertEqual(browser.previewPhoto?.lastPathComponent, "photo10.jpg")
        XCTAssertEqual(browser.tab, .viewer)
        browser.closePreview()
        XCTAssertNil(browser.previewPhoto)

        // 다른 폴더로 가면 크게 보기가 닫힙니다.
        browser.preview(try XCTUnwrap(browser.selectedPhoto))
        browser.open(folder: folder.appendingPathComponent("하위 폴더"))
        XCTAssertNil(browser.previewPhoto)
    }

    func testSorting() {
        let a = URL(fileURLWithPath: "/x/b.png")
        let b = URL(fileURLWithPath: "/x/a10.jpg")
        let c = URL(fileURLWithPath: "/x/a2.heic")
        let now = Date()
        let info: [URL: FolderBrowser.FileInfo] = [
            a: .init(modified: now, size: 300),
            b: .init(modified: now.addingTimeInterval(-100), size: 100),
            c: .init(modified: now.addingTimeInterval(-50), size: 200)
        ]
        func names(_ sort: PhotoSort, _ ascending: Bool = true) -> [String] {
            FolderBrowser.sorted([a, b, c], info: info, by: sort, ascending: ascending).map(\.lastPathComponent)
        }
        XCTAssertEqual(names(.name), ["a2.heic", "a10.jpg", "b.png"])
        XCTAssertEqual(names(.name, false), ["b.png", "a10.jpg", "a2.heic"])
        XCTAssertEqual(names(.date), ["a10.jpg", "a2.heic", "b.png"])
        XCTAssertEqual(names(.size, false), ["b.png", "a2.heic", "a10.jpg"])
        XCTAssertEqual(names(.type), ["a2.heic", "a10.jpg", "b.png"])
    }

    func testFolderContainment() {
        let parent = URL(fileURLWithPath: "/Users/me/Pictures", isDirectory: true)
        XCTAssertTrue(parent.contains(URL(fileURLWithPath: "/Users/me/Pictures/2024/trip")))
        XCTAssertTrue(parent.contains(parent))
        XCTAssertFalse(parent.contains(URL(fileURLWithPath: "/Users/me/Pictures2")))
        XCTAssertTrue(URL(fileURLWithPath: "/").contains(parent))
    }

    @MainActor
    func testUnsavedEditsAskBeforeNavigating() {
        let browser = FolderBrowser(launchArguments: ["MyPSX", folder.path])
        var navigated = false
        browser.hasUnsavedEdits = true
        browser.requestNavigation { navigated = true }
        XCTAssertFalse(navigated)
        XCTAssertNotNil(browser.pendingNavigation)

        browser.hasUnsavedEdits = false
        browser.requestNavigation { navigated = true }
        XCTAssertTrue(navigated)
    }

    @MainActor
    func testFavoritesToggle() {
        let browser = FolderBrowser(launchArguments: ["MyPSX", folder.path])
        let wasFavorite = browser.isFavorite(folder)
        browser.toggleFavorite(folder)
        XCTAssertNotEqual(browser.isFavorite(folder), wasFavorite)
        browser.toggleFavorite(folder)
        XCTAssertEqual(browser.isFavorite(folder), wasFavorite)
    }

    // MARK: 편집 흐름

    @MainActor
    func testEditUndoRedoAndSave() async throws {
        let source = folder.appendingPathComponent("photo10.jpg")
        let editor = PhotoEditor(url: source)
        await editor.load()
        XCTAssertEqual(editor.image?.width, 40)
        XCTAssertEqual(editor.image?.height, 20)
        XCTAssertFalse(editor.isModified)
        XCTAssertTrue(editor.canOverwriteOriginal)

        // 회전
        editor.rotate(clockwise: true)
        try await waitForIdle(editor)
        XCTAssertEqual(editor.image?.width, 20)
        XCTAssertEqual(editor.image?.height, 40)
        XCTAssertTrue(editor.isModified)

        // 자르기는 선택 영역 없이 시작 (드래그해서 고름)
        editor.beginCrop()
        XCTAssertEqual(editor.mode, .crop)
        XCTAssertFalse(editor.hasCropSelection)
        // 비율 1:1 버튼을 누르면 가운데에 가장 큰 영역
        editor.resetCropRect(aspect: 1)
        XCTAssertEqual(editor.cropRect, CGRect(x: 0, y: 10, width: 20, height: 20))
        editor.applyCrop()
        try await waitForIdle(editor)
        XCTAssertEqual(editor.mode, .view)
        XCTAssertEqual(editor.image?.width, 20)
        XCTAssertEqual(editor.image?.height, 20)

        // 자르기 취소는 이미지를 바꾸지 않습니다.
        editor.beginCrop()
        editor.cancelCrop()
        XCTAssertEqual(editor.image?.width, 20)

        // 크기 조절
        editor.resize(width: 8, height: 8)
        try await waitForIdle(editor)
        XCTAssertEqual(editor.image?.width, 8)

        // 실행 취소 3번이면 원본으로 돌아옵니다.
        editor.undo(); editor.undo(); editor.undo()
        XCTAssertEqual(editor.image?.width, 40)
        XCTAssertFalse(editor.isModified)
        XCTAssertFalse(editor.canUndo)

        // 다시 실행
        editor.redo()
        XCTAssertEqual(editor.image?.width, 20)
        XCTAssertEqual(editor.image?.height, 40)
        XCTAssertTrue(editor.isModified)

        // 다른 이름으로 저장
        let copy = folder.appendingPathComponent("photo10_편집.png")
        let savedCopy = await editor.save(to: copy)
        XCTAssertTrue(savedCopy)
        XCTAssertFalse(editor.isModified)
        let reloaded = try ImageLoader.loadFullImage(copy)
        XCTAssertEqual(reloaded.width, 20)
        XCTAssertEqual(reloaded.height, 40)

        // 원본 덮어쓰기
        editor.rotate(clockwise: false)
        try await waitForIdle(editor)
        let savedOriginal = await editor.save(to: source)
        XCTAssertTrue(savedOriginal)
        let original = try ImageLoader.loadFullImage(source)
        XCTAssertEqual(original.width, 40)
        XCTAssertEqual(original.height, 20)
    }

    @MainActor
    func testRevertAndFillBackground() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo2.png"))
        await editor.load()
        let original = try XCTUnwrap(editor.image)

        editor.resize(width: 10, height: 10)
        try await waitForIdle(editor)
        editor.revertToSaved()
        XCTAssertTrue(editor.image === original)
        XCTAssertFalse(editor.isModified)
        // 원래대로도 실행 취소할 수 있습니다.
        editor.undo()
        XCTAssertEqual(editor.image?.width, 10)

        editor.fillBackground(CGColor(gray: 1, alpha: 1))
        try await waitForIdle(editor)
        XCTAssertEqual(editor.image?.hasAlpha, false)
        XCTAssertFalse(editor.hasTransparency)
    }

    @MainActor
    func testSaveAndCopyCropSelectionKeepsPhoto() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo10.jpg"))
        await editor.load()
        let original = try XCTUnwrap(editor.image)
        editor.beginCrop()
        editor.cropRect = CGRect(x: 5, y: 2, width: 12, height: 8)

        let url = folder.appendingPathComponent("photo10_선택.png")
        let saved = await editor.saveSelection(to: url)
        XCTAssertTrue(saved)
        let written = try ImageLoader.loadFullImage(url)
        XCTAssertEqual(written.width, 12)
        XCTAssertEqual(written.height, 8)

        XCTAssertTrue(editor.copySelectionToClipboard())
        XCTAssertNotNil(NSPasteboard.general.data(forType: .png))

        // 편집 중인 사진과 자르기 상태는 그대로
        XCTAssertTrue(editor.image === original)
        XCTAssertEqual(editor.mode, .crop)
        XCTAssertFalse(editor.isModified)
    }

    @MainActor
    func testPlaceSelectionOnWhiteSquare() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo10.jpg"))
        await editor.load()
        editor.beginCrop()
        editor.cropRect = CGRect(x: 0, y: 0, width: 20, height: 10)

        editor.beginPlace(canvasSize: 100, margin: 0.1)
        XCTAssertEqual(editor.mode, .place)
        XCTAssertEqual(editor.placeCanvas, CGSize(width: 100, height: 100))
        // 긴 변이 80px(여백 10%)이 되도록 커지고 가운데에
        XCTAssertEqual(editor.placeRect, CGRect(x: 10, y: 30, width: 80, height: 40))
        XCTAssertEqual(editor.placementScale, 0.8, accuracy: 0.001)

        // 크기를 줄여도 가운데는 그대로
        editor.setPlacementScale(0.4)
        XCTAssertEqual(editor.placeRect, CGRect(x: 30, y: 40, width: 40, height: 20))

        // 취소하면 자르기로 돌아가고 사진은 그대로
        editor.cancelPlace()
        XCTAssertEqual(editor.mode, .crop)
        XCTAssertEqual(editor.image?.width, 40)

        // 배경을 200으로 바꾸면 이미지도 같은 비율로 따라감
        editor.beginPlace(canvasSize: 100, margin: 0)
        editor.setPlaceCanvas(size: 200)
        XCTAssertEqual(editor.placeRect, CGRect(x: 0, y: 50, width: 200, height: 100))

        // 꽉 차게 놓으면 좌우 끝에 딱 맞음
        XCTAssertEqual(PlaceOverlay.touchingEdges(of: editor.placeRect, canvas: editor.placeCanvas), [.left, .right])
        editor.placeRect.origin.y = 0
        XCTAssertEqual(PlaceOverlay.touchingEdges(of: editor.placeRect, canvas: editor.placeCanvas), [.left, .right, .top])
        XCTAssertEqual(PlaceOverlay.touchingEdges(of: CGRect(x: 1, y: 1, width: 10, height: 10),
                                                  canvas: editor.placeCanvas), [])
        editor.applyPlace()
        try await waitForIdle(editor)
        let result = try XCTUnwrap(editor.image)
        XCTAssertEqual(editor.mode, .view)
        XCTAssertEqual(result.width, 200)
        XCTAssertEqual(result.height, 200)
        XCTAssertFalse(result.hasAlpha)
        // 파란 이미지는 위쪽 절반에만, 아래쪽은 흰 배경 (JPG 테두리 오차 1px 허용)
        let bounds = try XCTUnwrap(ImageOps.contentBounds(result))
        XCTAssertEqual(bounds.minY, 0, accuracy: 1)
        XCTAssertEqual(bounds.maxY, 100, accuracy: 2)
        XCTAssertTrue(editor.canUndo)
        editor.undo()
        XCTAssertEqual(editor.image?.width, 40)
    }

    @MainActor
    func testCanvasZoomKeepsPointUnderCursor() {
        let zoom = CanvasZoom()
        zoom.viewport = CGSize(width: 1000, height: 800)
        zoom.fittedSize = CGSize(width: 500, height: 400)
        let fitted = CGRect(x: 250, y: 200, width: 500, height: 400)

        // 사진 오른쪽 아래 1/4 지점을 기준으로 4배
        let anchor = CGPoint(x: 625, y: 500)
        zoom.zoom(by: 4, anchor: anchor)
        XCTAssertEqual(zoom.scale, 4)
        let frame = zoom.frame(fitted: fitted)
        XCTAssertEqual(frame.width, 2000)
        XCTAssertEqual((anchor.x - frame.minX) / frame.width, 0.75, accuracy: 0.001)
        XCTAssertEqual((anchor.y - frame.minY) / frame.height, 0.75, accuracy: 0.001)

        // 너무 멀리 끌어도 사진이 화면 밖으로 사라지지 않음
        zoom.pan(by: CGSize(width: 5000, height: 0))
        XCTAssertEqual(zoom.offset.width, 540)   // (2000 - 1000) / 2 + 여유 40
        zoom.reset()
        XCTAssertFalse(zoom.isZoomed)

        // 맞춤 크기에서는 이동하지 않음, 최대 배율 제한
        zoom.pan(by: CGSize(width: 100, height: 100))
        XCTAssertEqual(zoom.offset, .zero)
        zoom.zoom(by: 1000)
        XCTAssertEqual(zoom.scale, CanvasZoom.range.upperBound)
    }

    @MainActor
    func testAdjustmentPreviewAndApply() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo2.png"))
        await editor.load()
        let original = try XCTUnwrap(editor.image)

        editor.updateAdjustmentPreview(ImageAdjustments(brightness: 50))
        XCTAssertTrue(editor.isAdjusting)
        XCTAssertFalse(editor.canEdit)
        try await waitUntil { editor.previewImage != nil }
        // 미리보기 중에는 원본이 그대로입니다.
        XCTAssertTrue(editor.image === original)

        // 0으로 되돌리면 미리보기가 끝납니다.
        editor.updateAdjustmentPreview(ImageAdjustments())
        XCTAssertFalse(editor.isAdjusting)
        XCTAssertNil(editor.previewImage)

        editor.updateAdjustmentPreview(ImageAdjustments(saturation: -100))
        editor.applyAdjustments(ImageAdjustments(saturation: -100))
        XCTAssertNil(editor.previewImage)
        try await waitForIdle(editor)
        XCTAssertFalse(editor.image === original)
        XCTAssertEqual(editor.image?.width, original.width)
        XCTAssertTrue(editor.isModified)
        editor.undo()
        XCTAssertTrue(editor.image === original)
    }

    @MainActor
    func testGPTEditFailureShowsErrorAndKeepsImage() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo2.png"))
        await editor.load()
        let original = try XCTUnwrap(editor.image)

        // 존재하지 않는 주소로 보내 실패를 일으킵니다. (실제 OpenAI 호출 없음)
        let client = OpenAIImageClient(apiKey: "sk-test", baseURL: URL(string: "http://127.0.0.1:9")!)
        editor.aiEdit(client, prompt: "test")
        XCTAssertTrue(editor.isBusy)
        try await waitForIdle(editor, timeout: 30)
        XCTAssertNotNil(editor.errorMessage)
        XCTAssertTrue(editor.image === original)
        XCTAssertFalse(editor.canUndo)
    }

    @MainActor
    func testAIBackgroundRemovalIsWhiteByDefault() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo2.png"))
        await editor.load()
        let original = try XCTUnwrap(editor.image)
        let ai = FakeAIEditor()

        editor.aiRemoveBackground(ai, transparent: false)
        try await waitForIdle(editor)
        XCTAssertNil(editor.errorMessage)
        XCTAssertEqual(ai.prompts, [AIPrompts.whiteBackground])
        XCTAssertEqual(ai.transparentFlags, [false])
        // 기본 지시문: 상품만 남기고 아이콘·글자·배경을 흰색으로
        for word in ["product", "icons", "text", "background", "white"] {
            XCTAssertTrue(AIPrompts.whiteBackground.contains(word), word)
        }
        XCTAssertFalse(editor.image === original)
        XCTAssertEqual(editor.image?.hasAlpha, false)
    }

    @MainActor
    func testAIBackgroundRemovalSharpensAfterwardsWithoutTouchingThePrompt() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo2.png"))
        await editor.load()
        let ai = FakeAIEditor()

        editor.aiRemoveBackground(ai, transparent: false, sharpen: 30)
        try await waitForIdle(editor)
        XCTAssertNil(editor.errorMessage)
        // 선명하게는 맥에서 처리하고, AI에는 상품을 건드리지 말라고만 합니다.
        XCTAssertEqual(ai.prompts, [AIPrompts.whiteBackground])
        XCTAssertTrue(AIPrompts.whiteBackground.contains("Do not redraw"))
        XCTAssertFalse(AIPrompts.whiteBackground.lowercased().contains("make it sharper"))
        XCTAssertEqual(editor.image?.width, 30)
        XCTAssertEqual(editor.image?.hasAlpha, false)
    }

    func testBackgroundJobOutputNamesAndFormats() throws {
        let source = folder.appendingPathComponent("photo10.jpg")
        XCTAssertEqual(BackgroundJobs.outputURL(for: source, fileExtension: "jpg").lastPathComponent, "photo10-1.jpg")
        try Data().write(to: folder.appendingPathComponent("photo10-1.jpg"))
        XCTAssertEqual(BackgroundJobs.outputURL(for: source, fileExtension: "jpg").lastPathComponent, "photo10-2.jpg")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("photo10-1.jpg"))

        var options = CutoutOptions()
        XCTAssertEqual(options.fileExtension(for: source, hasAlpha: false), "jpg")
        XCTAssertEqual(options.fileExtension(for: source, hasAlpha: true), "png")
        options.format = .png
        XCTAssertEqual(options.fileExtension(for: source, hasAlpha: false), "png")
        options.format = .jpg
        XCTAssertEqual(options.fileExtension(for: folder.appendingPathComponent("photo2.png"), hasAlpha: false), "jpg")
    }

    @MainActor
    func testBackgroundJobSavesNextToOriginalWhileEditorStaysFree() async throws {
        let jobs = BackgroundJobs()
        var saved: URL?
        jobs.onSaved = { saved = $0 }
        let source = folder.appendingPathComponent("photo2.png")
        let image = try ImageLoader.loadFullImage(source)
        var options = CutoutOptions()
        options.fitToSquare = true
        options.squareSize = 64

        jobs.removeBackground(source: source, image: image, ai: FakeAIEditor(), options: options)
        XCTAssertTrue(jobs.isRunning(source))
        // 같은 사진을 또 맡기면 무시
        jobs.removeBackground(source: source, image: image, ai: FakeAIEditor(), options: options)
        XCTAssertEqual(jobs.jobs.count, 1)

        for _ in 0..<200 where saved == nil { try await Task.sleep(for: .milliseconds(20)) }
        let url = try XCTUnwrap(saved)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "photo2-1.png")
        XCTAssertEqual(url.deletingLastPathComponent().resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
        XCTAssertFalse(jobs.isRunning(source))
        // 쇼핑몰 규격: 64 × 64 정사각형
        let written = try ImageLoader.loadFullImage(url)
        XCTAssertEqual(written.width, 64)
        XCTAssertEqual(written.height, 64)
    }

    @MainActor
    func testBackgroundJobCancelAndRetry() async throws {
        let jobs = BackgroundJobs()
        var saved: URL?
        jobs.onSaved = { saved = $0 }
        let source = folder.appendingPathComponent("photo10.jpg")
        let image = try ImageLoader.loadFullImage(source)
        let slow = FakeAIEditor(delay: 5)

        jobs.removeBackground(source: source, image: image, ai: slow, options: CutoutOptions())
        let id = try XCTUnwrap(jobs.jobs.first?.id)
        jobs.cancel(id)
        for _ in 0..<200 where jobs.isRunning(source) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(jobs.jobs.first?.status, .cancelled)
        XCTAssertNil(saved)

        slow.delay = 0
        jobs.retry(id)
        XCTAssertTrue(jobs.isRunning(source))
        for _ in 0..<200 where saved == nil { try await Task.sleep(for: .milliseconds(20)) }
        let url = try XCTUnwrap(saved)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "photo10-1.jpg")
        jobs.clearFinished()
        XCTAssertTrue(jobs.jobs.isEmpty)
    }

    @MainActor
    func testRenameAndResultFilter() async throws {
        XCTAssertTrue(FolderBrowser.isNumberedResult(URL(fileURLWithPath: "/a/상품-1.png")))
        XCTAssertTrue(FolderBrowser.isNumberedResult(URL(fileURLWithPath: "/a/IMG_0001-12.jpg")))
        XCTAssertFalse(FolderBrowser.isNumberedResult(URL(fileURLWithPath: "/a/IMG_0001.jpg")))
        XCTAssertFalse(FolderBrowser.isNumberedResult(URL(fileURLWithPath: "/a/2024-summer.jpg")))

        let browser = FolderBrowser(launchArguments: [])
        let original = folder.appendingPathComponent("photo2.png")
        let renamed = try XCTUnwrap(browser.rename(original, to: "새 이름"))
        XCTAssertEqual(renamed.lastPathComponent, "새 이름.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        _ = browser.rename(renamed, to: "photo2.png")
    }

    @MainActor
    func testAIBackgroundRemovalTransparentUsesProviderWhenSupported() async throws {
        let editor = PhotoEditor(url: folder.appendingPathComponent("photo2.png"))
        await editor.load()
        let ai = FakeAIEditor(supportsTransparentBackground: true)

        editor.aiRemoveBackground(ai, transparent: true)
        try await waitForIdle(editor)
        XCTAssertNil(editor.errorMessage)
        XCTAssertEqual(ai.prompts, [AIPrompts.transparentBackground])
        XCTAssertEqual(ai.transparentFlags, [true])
        XCTAssertEqual(editor.image?.hasAlpha, true)
    }

    @MainActor
    func testCropAspectRatios() {
        let size = CGSize(width: 4000, height: 3000)
        XCTAssertNil(CropAspect.free.ratio(for: size))
        XCTAssertEqual(CropAspect.original.ratio(for: size)!, 4.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(CropAspect.sixteenNine.ratio(for: size)!, 16.0 / 9.0, accuracy: 0.0001)
    }

    // MARK: 배경 제거 (실제 사진)

    /// 배경 제거는 Neural Engine/GPU가 있는 실제 Mac에서만 동작합니다 (GitHub의 가상 머신에서는 불가).
    /// 실행 예: PSX_SUBJECT_PHOTO="/Library/User Pictures/Animals/Zebra.heic" swift test
    @MainActor
    func testRemoveBackgroundOnRealPhoto() async throws {
        guard let path = ProcessInfo.processInfo.environment["PSX_SUBJECT_PHOTO"], !path.isEmpty else {
            throw XCTSkip("PSX_SUBJECT_PHOTO 환경 변수가 없어 건너뜁니다.")
        }
        let editor = PhotoEditor(url: URL(fileURLWithPath: path))
        await editor.load()
        let original = try XCTUnwrap(editor.image)
        XCTAssertNil(editor.loadError)

        editor.removeBackground(transparent: true)
        try await waitForIdle(editor, timeout: 120)
        XCTAssertNil(editor.errorMessage)

        let result = try XCTUnwrap(editor.image)
        XCTAssertFalse(result === original, "배경 제거 결과가 없습니다.")
        XCTAssertEqual(result.width, original.width)
        XCTAssertEqual(result.height, original.height)
        XCTAssertTrue(result.hasAlpha)

        let transparent = transparentFraction(of: result)
        print("배경 제거: 투명한 픽셀 비율 \(Int(transparent * 100))%")
        XCTAssertGreaterThan(transparent, 0.05, "배경이 거의 지워지지 않았습니다.")
        XCTAssertLessThan(transparent, 0.95, "피사체까지 지워졌습니다.")

        // PNG로 저장하면 투명도가 유지됩니다.
        let output = folder.appendingPathComponent("subject.png")
        let saved = await editor.save(to: output)
        XCTAssertTrue(saved)
        XCTAssertTrue(try ImageLoader.loadFullImage(output).hasAlpha)
    }

    // MARK: 도우미

    @MainActor
    private func waitForIdle(_ editor: PhotoEditor, timeout: TimeInterval = 10) async throws {
        try await waitUntil(timeout: timeout) { !editor.isBusy }
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("시간 초과")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func transparentFraction(of image: CGImage) -> Double {
        // 계산을 빠르게 하려고 작게 줄여서 셉니다.
        let width = 128
        let height = max(1, Int(Double(image.height) / Double(image.width) * 128))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var transparent = 0
        for i in stride(from: 3, to: bytes.count, by: 4) where bytes[i] < 16 {
            transparent += 1
        }
        return Double(transparent) / Double(width * height)
    }
}

/// 정해 둔 결과를 돌려주는 가짜 AI (네트워크 / Codex 없음)
final class FakeAIEditor: AIImageEditor, @unchecked Sendable {
    let supportsTransparentBackground: Bool
    var displayName: String { "Fake" }
    private let lock = NSLock()
    private var _prompts: [String] = []
    private var _transparentFlags: [Bool] = []

    /// 결과를 내기 전 기다리는 시간(초). 취소 테스트용
    var delay: Double = 0

    init(supportsTransparentBackground: Bool = false, delay: Double = 0) {
        self.supportsTransparentBackground = supportsTransparentBackground
        self.delay = delay
    }

    var prompts: [String] { lock.lock(); defer { lock.unlock() }; return _prompts }
    var transparentFlags: [Bool] { lock.lock(); defer { lock.unlock() }; return _transparentFlags }

    func edit(_ image: CGImage, prompt: String, transparentBackground: Bool) async throws -> CGImage {
        lock.lock()
        _prompts.append(prompt)
        _transparentFlags.append(transparentBackground)
        lock.unlock()
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let alpha = transparentBackground
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast
                                                   : CGImageAlphaInfo.noneSkipLast).rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width / 2, height: image.height))
        return context.makeImage()!
    }
}
