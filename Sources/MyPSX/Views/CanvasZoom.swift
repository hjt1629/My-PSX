import AppKit
import SwiftUI

/// 가운데 사진의 확대 / 이동 상태. scale 1 = 화면에 맞춤
@MainActor
final class CanvasZoom: ObservableObject {
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var offset: CGSize = .zero

    static let range: ClosedRange<CGFloat> = 0.25...32

    /// 마지막으로 그린 캔버스 크기와 '맞춤' 크기 (이동 범위 계산용)
    var viewport: CGSize = .zero
    var fittedSize: CGSize = .zero

    var isZoomed: Bool { scale != 1 || offset != .zero }

    func reset() {
        scale = 1
        offset = .zero
    }

    /// anchor(캔버스 좌표)가 가리키는 사진 위치가 그대로 있도록 확대 / 축소합니다. nil이면 가운데 기준.
    func zoom(by factor: CGFloat, anchor: CGPoint? = nil) {
        let newScale = min(max(scale * factor, Self.range.lowerBound), Self.range.upperBound)
        let f = newScale / scale
        let point = anchor ?? CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let center = CGPoint(x: viewport.width / 2 + offset.width, y: viewport.height / 2 + offset.height)
        let newCenter = CGPoint(x: point.x + (center.x - point.x) * f, y: point.y + (center.y - point.y) * f)
        scale = newScale
        offset = clamped(CGSize(width: newCenter.x - viewport.width / 2, height: newCenter.y - viewport.height / 2))
    }

    func pan(by delta: CGSize) {
        offset = clamped(CGSize(width: offset.width + delta.width, height: offset.height + delta.height))
    }

    /// 사진이 화면보다 클 때만, 가장자리가 너무 안쪽으로 들어오지 않게 움직일 수 있습니다.
    private func clamped(_ value: CGSize) -> CGSize {
        let margin: CGFloat = 40
        let maxX = max(0, (fittedSize.width * scale - viewport.width) / 2 + margin)
        let maxY = max(0, (fittedSize.height * scale - viewport.height) / 2 + margin)
        return CGSize(width: min(max(value.width, -maxX), maxX),
                      height: min(max(value.height, -maxY), maxY))
    }

    /// 맞춤 크기의 사진을 확대 / 이동한 화면 위치
    func frame(fitted: CGRect) -> CGRect {
        let width = fitted.width * scale, height = fitted.height * scale
        return CGRect(x: fitted.midX + offset.width - width / 2,
                      y: fitted.midY + offset.height - height / 2,
                      width: width, height: height)
    }
}

/// 캔버스 위의 트랙패드 핀치(확대 / 축소)와 두 손가락 스크롤(이동), 마우스 휠(확대 / 축소)을 받습니다.
/// 클릭은 가로채지 않아 자르기 상자 조작은 그대로 동작합니다.
struct CanvasEventCatcher: NSViewRepresentable {
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onScroll: (NSEvent, CGPoint) -> Bool

    func makeNSView(context: Context) -> PassThroughView {
        let view = PassThroughView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: PassThroughView, context: Context) {
        context.coordinator.onMagnify = onMagnify
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ view: PassThroughView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMagnify: onMagnify, onScroll: onScroll)
    }

    final class PassThroughView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var onMagnify: (CGFloat, CGPoint) -> Void
        var onScroll: (NSEvent, CGPoint) -> Bool
        private var monitor: Any?

        init(onMagnify: @escaping (CGFloat, CGPoint) -> Void, onScroll: @escaping (NSEvent, CGPoint) -> Bool) {
            self.onMagnify = onMagnify
            self.onScroll = onScroll
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
                // 이벤트 모니터는 메인 스레드에서 불립니다.
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }

        /// 캔버스 위에서 일어난 이벤트면 처리하고 true
        private func handle(_ event: NSEvent) -> Bool {
            guard let view, let window = view.window, event.window === window else { return false }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return false }
            switch event.type {
            case .magnify:
                onMagnify(event.magnification, point)
                return true
            case .scrollWheel:
                return onScroll(event, point)
            default:
                return false
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
