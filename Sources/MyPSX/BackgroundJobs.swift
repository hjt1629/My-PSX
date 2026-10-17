import CoreGraphics
import Foundation
import PSXCore

/// AI 배경 제거를 사진마다 뒤에서 따로 돌립니다.
/// 한 장을 맡겨 두고 다른 사진을 열어 또 맡길 수 있고, 끝나면 같은 폴더에 `원래이름-1`로 바로 저장합니다.
@MainActor
final class BackgroundJobs: ObservableObject {
    struct Job: Identifiable {
        enum Status: Equatable {
            case running
            case saved(URL)
            case failed(String)
        }

        let id = UUID()
        let source: URL
        let started = Date()
        var status: Status = .running
        var seconds: Int?
    }

    @Published private(set) var jobs: [Job] = []
    /// 실패하면 보여 줄 오류
    @Published var errorMessage: String?

    /// 저장이 끝나면 불립니다 (목록 새로 고침 등)
    var onSaved: ((URL) -> Void)?

    var runningCount: Int { jobs.filter { $0.status == .running }.count }

    func isRunning(_ url: URL) -> Bool {
        jobs.contains { $0.status == .running && $0.source.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
    }

    /// 가장 최근에 끝난 작업 (아래 막대에 잠깐 표시)
    var lastFinished: Job? {
        jobs.last { $0.status != .running }
    }

    /// image: 지금 편집 화면의 사진 (자르기 등 편집 내용 포함). 원본 파일은 건드리지 않습니다.
    func removeBackground(source: URL, image: CGImage, ai: any AIImageEditor, transparent: Bool, sharpen: Double) {
        guard !isRunning(source) else { return }
        let job = Job(source: source)
        jobs.append(job)
        Task {
            do {
                let saved = try await Task.detached(priority: .userInitiated) {
                    var result = try await ai.removeBackground(image, transparent: transparent)
                    if sharpen > 0 {
                        result = try ImageOps.adjust(result, ImageAdjustments(sharpness: min(sharpen, 100)))
                    }
                    let destination = Self.outputURL(for: source, hasAlpha: result.hasAlpha)
                    try ImageExporter.write(result, to: destination, metadataFrom: source)
                    return destination
                }.value
                finish(job.id, .saved(saved))
                onSaved?(saved)
            } catch {
                finish(job.id, .failed(error.localizedDescription))
                errorMessage = "\(source.lastPathComponent) 배경 제거 실패\n\(error.localizedDescription)"
            }
        }
    }

    private func finish(_ id: UUID, _ status: Job.Status) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
        jobs[index].seconds = Int(Date().timeIntervalSince(jobs[index].started).rounded())
        // 끝난 기록은 최근 20개만 남깁니다.
        let finished = jobs.indices.filter { jobs[$0].status != .running }
        if finished.count > 20 { jobs.remove(at: finished[0]) }
    }

    /// `사진.jpg` → `사진-1.jpg` (이미 있으면 -2, -3 …). 투명 배경이면 PNG.
    nonisolated static func outputURL(for source: URL, hasAlpha: Bool) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let original = source.pathExtension.lowercased()
        let fileExtension = hasAlpha ? "png" : (ImageExporter.canWrite(fileExtension: original) ? original : "jpg")
        var number = 1
        while true {
            let candidate = folder.appendingPathComponent("\(base)-\(number).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}
