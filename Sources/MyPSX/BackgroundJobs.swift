import CoreGraphics
import Foundation
import PSXCore
import SwiftUI

/// 배경 제거 뒤 마무리와 저장 방법 (오려내기 탭의 설정)
struct CutoutOptions: Sendable, Equatable {
    enum Format: String, CaseIterable, Identifiable, Sendable {
        case original, jpg, png
        var id: Self { self }
        var title: String {
            switch self {
            case .original: return "원본과 같게"
            case .jpg: return "JPG"
            case .png: return "PNG"
            }
        }
    }

    var transparent = false
    /// 0~100. 맥에서 처리해 상품 모양은 바뀌지 않음
    var sharpen = 30.0
    /// 쇼핑몰 규격: 정사각형 캔버스 가운데에 여백을 두고 배치
    var fitToSquare = false
    var squareSize = 1000
    /// 0~0.4
    var margin = 0.1
    var format: Format = .original

    /// 결과 이미지에 마무리를 적용합니다.
    func finish(_ image: CGImage) throws -> CGImage {
        var result = image
        if sharpen > 0 {
            result = try ImageOps.adjust(result, ImageAdjustments(sharpness: min(sharpen, 100)))
        }
        if fitToSquare {
            result = try ImageOps.fitToSquare(result, size: squareSize, margin: margin, transparent: transparent)
        }
        return result
    }

    /// 저장할 확장자. 투명이 필요하면 PNG를 씁니다.
    func fileExtension(for source: URL, hasAlpha: Bool) -> String {
        let original = source.pathExtension.lowercased()
        switch format {
        case .png: return "png"
        case .jpg: return hasAlpha ? "png" : "jpg"
        case .original:
            if hasAlpha { return "png" }
            return ImageExporter.canWrite(fileExtension: original) ? original : "jpg"
        }
    }
}

/// 오려내기 탭의 설정을 한곳에서 읽고 씁니다.
struct CutoutSettings: DynamicProperty {
    @AppStorage("cutoutTransparent") var transparent = false
    @AppStorage("cutoutSharpen") var sharpen = 30.0
    @AppStorage("shopFitEnabled") var fitToSquare = false
    @AppStorage("shopFitSize") var squareSize = 1000
    @AppStorage("shopFitMargin") var margin = 0.1
    @AppStorage("cutoutFormat") var format: CutoutOptions.Format = .original

    var options: CutoutOptions {
        CutoutOptions(transparent: transparent, sharpen: sharpen, fitToSquare: fitToSquare,
                      squareSize: squareSize, margin: margin, format: format)
    }
}

/// AI 배경 제거를 사진마다 뒤에서 따로 돌립니다.
/// 한 장을 맡겨 두고 다른 사진을 열어 또 맡길 수 있고, 끝나면 같은 폴더에 `원래이름-1`로 바로 저장합니다.
@MainActor
final class BackgroundJobs: ObservableObject {
    struct Job: Identifiable {
        enum Status: Equatable {
            case running
            case saved(URL)
            case failed(String)
            case cancelled
        }

        let id = UUID()
        let source: URL
        var started = Date()
        var status: Status = .running
        var seconds: Int?

        var isRunning: Bool { status == .running }
    }

    /// 다시 하기에 필요한 원래 요청
    private struct Request: Sendable {
        let image: CGImage
        let ai: any AIImageEditor
        let options: CutoutOptions
    }

    @Published private(set) var jobs: [Job] = []
    /// 실패하면 보여 줄 오류
    @Published var errorMessage: String?

    /// 저장이 끝나면 불립니다 (목록 새로 고침 등)
    var onSaved: ((URL) -> Void)?

    private var requests: [UUID: Request] = [:]
    private var tasks: [UUID: Task<URL, Error>] = [:]

    var runningCount: Int { jobs.filter(\.isRunning).count }
    var failedCount: Int { jobs.filter { if case .failed = $0.status { return true } else { return false } }.count }

    func isRunning(_ url: URL) -> Bool {
        jobs.contains { $0.isRunning && $0.source.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
    }

    /// 가장 최근에 끝난 작업 (아래 막대에 잠깐 표시)
    var lastFinished: Job? {
        jobs.last { !$0.isRunning }
    }

    /// image: 지금 편집 화면의 사진 (자르기 등 편집 내용 포함). 원본 파일은 건드리지 않습니다.
    func removeBackground(source: URL, image: CGImage, ai: any AIImageEditor, options: CutoutOptions) {
        guard !isRunning(source) else { return }
        let job = Job(source: source)
        jobs.append(job)
        requests[job.id] = Request(image: image, ai: ai, options: options)
        start(job.id)
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
    }

    /// 실패하거나 취소한 작업을 같은 설정으로 다시 합니다.
    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isRunning,
              !isRunning(jobs[index].source), requests[id] != nil else { return }
        jobs[index].status = .running
        jobs[index].started = Date()
        jobs[index].seconds = nil
        start(id)
    }

    /// 실패한 작업을 모두 다시
    func retryFailed() {
        for job in jobs { if case .failed = job.status { retry(job.id) } }
    }

    /// 끝난 기록 지우기
    func clearFinished() {
        for job in jobs where !job.isRunning { requests[job.id] = nil }
        jobs.removeAll { !$0.isRunning }
    }

    private func start(_ id: UUID) {
        guard let request = requests[id], let source = jobs.first(where: { $0.id == id })?.source else { return }
        // 무거운 일은 메인 스레드 밖에서. 취소하면 이 작업(과 그 안의 Codex 실행)이 멈춥니다.
        let work = Task.detached(priority: .userInitiated) {
            let removed = try await request.ai.removeBackground(request.image, transparent: request.options.transparent)
            try Task.checkCancellation()
            let result = try request.options.finish(removed)
            try Task.checkCancellation()
            let destination = Self.outputURL(
                for: source, fileExtension: request.options.fileExtension(for: source, hasAlpha: result.hasAlpha))
            try ImageExporter.write(result, to: destination, metadataFrom: source)
            return destination
        }
        tasks[id] = work
        Task {
            do {
                let saved = try await work.value
                finish(id, .saved(saved))
                onSaved?(saved)
            } catch {
                if work.isCancelled || error is CancellationError {
                    finish(id, .cancelled)
                } else {
                    finish(id, .failed(error.localizedDescription))
                    errorMessage = "\(source.lastPathComponent) 배경 제거 실패\n\(error.localizedDescription)"
                }
            }
            tasks[id] = nil
        }
    }

    private func finish(_ id: UUID, _ status: Job.Status) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
        jobs[index].seconds = Int(Date().timeIntervalSince(jobs[index].started).rounded())
        if case .saved = status { requests[id] = nil }
        // 끝난 기록은 최근 30개만 남깁니다.
        let finished = jobs.filter { !$0.isRunning }
        if finished.count > 30, let oldest = finished.first {
            requests[oldest.id] = nil
            jobs.removeAll { $0.id == oldest.id }
        }
    }

    /// `사진.jpg` → `사진-1.jpg` (이미 있으면 -2, -3 …)
    nonisolated static func outputURL(for source: URL, fileExtension: String) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let candidate = folder.appendingPathComponent("\(base)-\(number).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}
