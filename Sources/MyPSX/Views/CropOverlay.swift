import SwiftUI

/// 사진 위에 자르기 영역을 그리고 드래그로 조절하게 해줍니다.
/// - 영역 밖에서 드래그: 새 영역 그리기
/// - 영역 안에서 드래그: 영역 이동
/// - 모서리 손잡이 드래그: 크기 조절
struct CropOverlay: View {
    /// 픽셀 단위, 왼쪽 위 원점
    @Binding var rect: CGRect
    let imageSize: CGSize
    /// 화면에 그려진 사진의 위치 (뷰 좌표)
    let imageFrame: CGRect
    /// 너비 / 높이. nil이면 자유 비율
    let aspect: CGFloat?

    @State private var dragMode: DragMode?
    @State private var startRect: CGRect = .zero

    private enum DragMode {
        case create
        case move
        case corner(Corner)
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }

        var opposite: Corner {
            switch self {
            case .topLeft: return .bottomRight
            case .topRight: return .bottomLeft
            case .bottomLeft: return .topRight
            case .bottomRight: return .topLeft
            }
        }
    }

    private var scale: CGFloat {
        imageSize.width > 0 ? imageFrame.width / imageSize.width : 1
    }

    var body: some View {
        let viewRect = toView(rect)
        ZStack {
            // 잘려나갈 부분 어둡게
            Path { path in
                path.addRect(imageFrame)
                path.addRect(viewRect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            // 3분할 안내선
            Path { path in
                for i in 1...2 {
                    let x = viewRect.minX + viewRect.width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: viewRect.minY))
                    path.addLine(to: CGPoint(x: x, y: viewRect.maxY))
                    let y = viewRect.minY + viewRect.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: viewRect.minX, y: y))
                    path.addLine(to: CGPoint(x: viewRect.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 0.5)

            Path { path in path.addRect(viewRect) }
                .stroke(Color.white, lineWidth: 1.5)

            ForEach(Corner.allCases, id: \.self) { corner in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(radius: 1)
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
                    let start = value.startLocation
                    if let corner = Corner.allCases.first(where: {
                        distance($0.point(in: viewRect), start) < 14
                    }) {
                        dragMode = .corner(corner)
                    } else if viewRect.contains(start) {
                        dragMode = .move
                    } else {
                        dragMode = .create
                    }
                }

                switch dragMode {
                case .move:
                    var moved = startRect.offsetBy(dx: value.translation.width / scale,
                                                   dy: value.translation.height / scale)
                    moved.origin.x = min(max(0, moved.origin.x), imageSize.width - moved.width)
                    moved.origin.y = min(max(0, moved.origin.y), imageSize.height - moved.height)
                    rect = moved
                case .create:
                    rect = makeRect(anchor: toImage(value.startLocation), to: toImage(value.location))
                case .corner(let corner):
                    rect = makeRect(anchor: corner.opposite.point(in: startRect), to: toImage(value.location))
                case nil:
                    break
                }
            }
            .onEnded { _ in
                dragMode = nil
            }
    }

    /// anchor를 고정점으로 point까지 이어지는 사각형. 비율이 정해져 있으면 맞춥니다.
    private func makeRect(anchor: CGPoint, to point: CGPoint) -> CGRect {
        var width = point.x - anchor.x
        var height = point.y - anchor.y

        if let aspect, aspect > 0 {
            let signX: CGFloat = width < 0 ? -1 : 1
            let signY: CGFloat = height < 0 ? -1 : 1
            var w = abs(width)
            var h = abs(height)
            if w / max(h, 0.0001) > aspect {
                w = h * aspect
            } else {
                h = w / aspect
            }
            // 사진 밖으로 나가지 않게
            let maxW = signX > 0 ? imageSize.width - anchor.x : anchor.x
            let maxH = signY > 0 ? imageSize.height - anchor.y : anchor.y
            if w > maxW { w = maxW; h = w / aspect }
            if h > maxH { h = maxH; w = h * aspect }
            width = w * signX
            height = h * signY
        }

        return CGRect(x: min(anchor.x, anchor.x + width),
                      y: min(anchor.y, anchor.y + height),
                      width: abs(width),
                      height: abs(height))
    }

    private func toView(_ r: CGRect) -> CGRect {
        CGRect(x: imageFrame.minX + r.minX * scale,
               y: imageFrame.minY + r.minY * scale,
               width: r.width * scale,
               height: r.height * scale)
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, (p.x - imageFrame.minX) / scale), imageSize.width),
                y: min(max(0, (p.y - imageFrame.minY) / scale), imageSize.height))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
