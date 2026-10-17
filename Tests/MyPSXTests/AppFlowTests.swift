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

        // 하위 폴더로 이동하면 편집 화면이 닫힙니다.
        browser.open(folder: folder.appendingPathComponent("하위 폴더"))
        XCTAssertNil(browser.openedPhoto)
        browser.goUp()
        XCTAssertEqual(browser.currentFolder?.path, folder.standardizedFileURL.path)
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

        // 뷰어 / 누끼 탭을 오가도 같은 편집 상태를 유지합니다.
        editor.rotate(clockwise: true)
        try await waitForIdle(editor)
        browser.switchTab(.viewer)
        browser.switchTab(.cutout)
        XCTAssertTrue(browser.editor === editor)
        XCTAssertTrue(editor.isModified)

        // 같은 사진을 다시 열어도 편집이 사라지지 않습니다.
        browser.openPhoto(editor.sourceURL)
        XCTAssertTrue(browser.editor === editor)

        // 다른 사진을 열면 새 편집 상태가 됩니다.
        browser.move(by: 1)
        XCTAssertFalse(browser.editor === editor)
        XCTAssertEqual(browser.editor?.sourceURL.lastPathComponent, "photo10.jpg")
        XCTAssertEqual(browser.tab, .cutout)

        // 다른 폴더를 열면 편집기를 닫고 뷰어로 돌아갑니다.
        browser.open(folder: folder.appendingPathComponent("하위 폴더"))
        XCTAssertNil(browser.editor)
        XCTAssertEqual(browser.tab, .viewer)
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

        // 자르기 (1:1)
        editor.beginCrop(aspect: 1)
        XCTAssertEqual(editor.mode, .crop)
        XCTAssertEqual(editor.cropRect, CGRect(x: 0, y: 10, width: 20, height: 20))
        editor.applyCrop()
        try await waitForIdle(editor)
        XCTAssertEqual(editor.mode, .view)
        XCTAssertEqual(editor.image?.width, 20)
        XCTAssertEqual(editor.image?.height, 20)

        // 자르기 취소는 이미지를 바꾸지 않습니다.
        editor.beginCrop(aspect: nil)
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

        editor.removeBackground()
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
