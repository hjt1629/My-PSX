import SwiftUI

/// 흰 배경 캔버스 위에 놓을 이미지를 그리고 드래그로 옮기거나 크기를 바꾸게 해줍니다.
/// - 이미지 안쪽 드래그: 이동 (캔버스 가운데에 가까워지면 딱 붙음)
/// - 모서리 손잡이 드래그: 비율을 지킨 채 크기 조절 (반대쪽 모서리 고정)
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
        // 가운데에서 화면상 6pt 안이면 딱 맞춥니다.
        let tolerance = 6 / scale
        let snapX = abs(moved.midX - canvasSize.width / 2) < tolerance
        let snapY = abs(moved.midY - canvasSize.height / 2) < tolerance
        if snapX { moved.origin.x = (canvasSize.width - moved.width) / 2 }
        if snapY { moved.origin.y = (canvasSize.height - moved.height) / 2 }
        snapped = (snapX, snapY)
        rect = moved
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
        let width = max(max(dx, dy * aspect), 8)
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
