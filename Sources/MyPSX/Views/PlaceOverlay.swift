import SwiftUI

/// 흰 배경 캔버스 위에 놓을 이미지를 그리고 드래그로 옮기거나 크기를 바꾸게 해줍니다.
/// - 이미지 안쪽 드래그: 이동 (캔버스 가운데·끝에 가까워지면 딱 붙음)
/// - 모서리 손잡이 드래그: 비율을 지킨 채 크기 조절 (반대쪽 모서리 고정, 캔버스 끝에 딱 붙음)
/// 이미지 가장자리가 캔버스 끝에 딱 맞으면 그 변을 초록 선으로 표시합니다.
/// 캔버스 밖으로 나간 부분은 잘려 보이고, 적용할 때도 잘립니다.
struct PlaceOverlay: View {
    /// 픽셀 단위, 왼쪽 위 원점
    @Binding var rect: CGRect
    let layer: CGImage
    let canvasSize: CGSize
    /// 화면에 그려진 캔버스의 위치 (뷰 좌표)
    let canvasFrame: CGRect

    @State private var dragMode: DragMode?
    @State private var startRect: CGRect = .zero
    @State private var snapped = (x: false, y: false)

    /// 화면상 이 거리(pt) 안으로 들어오면 딱 붙습니다.
    private let snapDistance: CGFloat = 6

    private enum DragMode {
        case move
        case corner(CropOverlay.Corner)
    }

    private var scale: CGFloat {
        canvasSize.width > 0 ? canvasFrame.width / canvasSize.width : 1
    }

    var body: some View {
        let viewRect = toView(rect)
        ZStack {
            Image(decorative: layer, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: max(viewRect.width, 1), height: max(viewRect.height, 1))
                .position(x: viewRect.midX, y: viewRect.midY)
                .mask {
                    Rectangle()
                        .frame(width: canvasFrame.width, height: canvasFrame.height)
                        .position(x: canvasFrame.midX, y: canvasFrame.midY)
                }

            // 가운데 맞춤 안내선
            Path { path in
                if snapped.x {
                    path.move(to: CGPoint(x: canvasFrame.midX, y: canvasFrame.minY))
                    path.addLine(to: CGPoint(x: canvasFrame.midX, y: canvasFrame.maxY))
                }
                if snapped.y {
                    path.move(to: CGPoint(x: canvasFrame.minX, y: canvasFrame.midY))
                    path.addLine(to: CGPoint(x: canvasFrame.maxX, y: canvasFrame.midY))
                }
            }
            .stroke(Color.pink, lineWidth: 1)

            Path { path in path.addRect(viewRect) }
                .stroke(Theme.accent, lineWidth: 1.5)

            // 캔버스 끝에 딱 맞은 변
            Path { path in
                for edge in touchingEdges {
                    let (from, to) = edge.line(in: canvasFrame)
                    path.move(to: from)
                    path.addLine(to: to)
                }
            }
            .stroke(Color.green, lineWidth: 3)

            ForEach(CropOverlay.Corner.allCases, id: \.self) { corner in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent, lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .position(corner.point(in: viewRect))
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragMode == nil {
                    startRect = rect
                    let viewRect = toView(rect)
                    if let corner = CropOverlay.Corner.allCases.first(where: {
                        hypot($0.point(in: viewRect).x - value.startLocation.x,
                              $0.point(in: viewRect).y - value.startLocation.y) < 14
                    }) {
                        dragMode = .corner(corner)
                    } else {
                        // 이미지 밖을 끌어도 옮길 수 있게 (작게 줄였을 때 편하도록)
                        dragMode = .move
                    }
                }
                switch dragMode {
                case .move:
                    move(by: value.translation)
                case .corner(let corner):
                    resize(corner: corner, to: value.location)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                dragMode = nil
                snapped = (false, false)
            }
    }

    private func move(by translation: CGSize) {
        var moved = startRect.offsetBy(dx: translation.width / scale, dy: translation.height / scale)
        let tolerance = snapDistance / scale
        // 왼쪽 끝 / 오른쪽 끝 / 가운데 중 가장 가까운 곳에 딱 맞춥니다.
        let x = Self.nearestSnap([(0 - moved.minX, false), (canvasSize.width - moved.maxX, false),
                                  (canvasSize.width / 2 - moved.midX, true)], tolerance: tolerance)
        let y = Self.nearestSnap([(0 - moved.minY, false), (canvasSize.height - moved.maxY, false),
                                  (canvasSize.height / 2 - moved.midY, true)], tolerance: tolerance)
        if let x { moved.origin.x += x.offset }
        if let y { moved.origin.y += y.offset }
        snapped = (x?.isCenter ?? false, y?.isCenter ?? false)
        rect = moved
    }

    /// (옮길 거리, 가운데인지) 후보 중 tolerance 안에서 가장 가까운 것
    private static func nearestSnap(_ candidates: [(CGFloat, Bool)], tolerance: CGFloat) -> (offset: CGFloat, isCenter: Bool)? {
        candidates.filter { abs($0.0) < tolerance }
            .min { abs($0.0) < abs($1.0) }
            .map { (offset: $0.0, isCenter: $0.1) }
    }

    // MARK: 끝 표시

    enum Edge: CaseIterable {
        case left, right, top, bottom

        var title: String {
            switch self {
            case .left: return "왼쪽"
            case .right: return "오른쪽"
            case .top: return "위"
            case .bottom: return "아래"
            }
        }

        func line(in frame: CGRect) -> (CGPoint, CGPoint) {
            switch self {
            case .left: return (CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX, y: frame.maxY))
            case .right: return (CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY))
            case .top: return (CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY))
            case .bottom: return (CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY))
            }
        }
    }

    /// 이미지 가장자리가 캔버스 끝에 딱 맞은 변들 (반 픽셀 오차 허용)
    private var touchingEdges: [Edge] {
        Self.touchingEdges(of: rect, canvas: canvasSize)
    }

    static func touchingEdges(of rect: CGRect, canvas: CGSize) -> [Edge] {
        let e: CGFloat = 0.5
        var edges: [Edge] = []
        if abs(rect.minX) < e { edges.append(.left) }
        if abs(rect.maxX - canvas.width) < e { edges.append(.right) }
        if abs(rect.minY) < e { edges.append(.top) }
        if abs(rect.maxY - canvas.height) < e { edges.append(.bottom) }
        return edges
    }

    private func resize(corner: CropOverlay.Corner, to location: CGPoint) {
        let anchor = corner.opposite.point(in: startRect)
        let point = CGPoint(x: (location.x - canvasFrame.minX) / scale, y: (location.y - canvasFrame.minY) / scale)
        let aspect = CGFloat(layer.width) / CGFloat(max(layer.height, 1))
        // 끌려는 방향 (손잡이가 반대쪽 모서리에서 어느 쪽에 있는지)
        let signX: CGFloat = (corner == .topRight || corner == .bottomRight) ? 1 : -1
        let signY: CGFloat = (corner == .bottomLeft || corner == .bottomRight) ? 1 : -1
        let dx = max(0, (point.x - anchor.x) * signX)
        let dy = max(0, (point.y - anchor.y) * signY)
        var width = max(max(dx, dy * aspect), 8)
        // 끌고 있는 변이 캔버스 끝에 가까우면 딱 맞춥니다. (가로 끝 또는 세로 끝 중 가까운 쪽)
        let tolerance = snapDistance / scale
        let edgeX = signX > 0 ? canvasSize.width : 0
        let edgeY = signY > 0 ? canvasSize.height : 0
        let widthToX = (edgeX - anchor.x) * signX
        let widthToY = (edgeY - anchor.y) * signY * aspect
        // 가로는 너비 차이, 세로는 높이 차이(= 너비 차이 / 비율)로 거리를 잽니다.
        let candidates = [widthToX, widthToY].enumerated()
            .filter { $0.element > 8 && abs($0.element - width) / ($0.offset == 0 ? 1 : aspect) < tolerance }
            .map(\.element)
        if let snap = candidates.min(by: { abs($0 - width) < abs($1 - width) }) {
            width = snap
        }
        let height = width / aspect
        rect = CGRect(x: signX > 0 ? anchor.x : anchor.x - width,
                      y: signY > 0 ? anchor.y : anchor.y - height,
                      width: width, height: height)
    }

    private func toView(_ r: CGRect) -> CGRect {
        CGRect(x: canvasFrame.minX + r.minX * scale,
               y: canvasFrame.minY + r.minY * scale,
               width: r.width * scale,
               height: r.height * scale)
    }
}
