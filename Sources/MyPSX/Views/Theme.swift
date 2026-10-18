import AppKit
import SwiftUI

/// PhotoScape X 느낌의 어두운 회색 테마
enum Theme {
    static let window = Color(red: 0.145, green: 0.145, blue: 0.155)
    static let panel = Color(red: 0.180, green: 0.180, blue: 0.190)
    static let raised = Color(red: 0.235, green: 0.235, blue: 0.245)
    static let hover = Color.white.opacity(0.07)
    static let canvas = Color(red: 0.105, green: 0.105, blue: 0.110)
    static let separator = Color.black.opacity(0.45)
    static let text = Color.white.opacity(0.90)
    static let secondaryText = Color.white.opacity(0.52)
    static let accent = Color(red: 0.30, green: 0.60, blue: 1.00)
    static let folder = Color(red: 0.45, green: 0.70, blue: 1.00)
}

/// 패널 사이 1px 구분선
struct PanelDivider: View {
    var vertical = true

    var body: some View {
        Theme.separator
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// 끌어서 옆 패널의 너비를 바꾸는 세로 구분선. 더블클릭하면 기본 너비로 돌아갑니다.
struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let defaultWidth: Double
    /// 오른쪽 패널이면 true (왼쪽으로 끌수록 넓어짐)
    var trailing = false
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        (hovering || startWidth != nil ? Theme.accent.opacity(0.7) : Theme.separator)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                if startWidth == nil { startWidth = width }
                                let delta = trailing ? -drag.translation.width : drag.translation.width
                                width = min(max((startWidth ?? width) + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
                    .onTapGesture(count: 2) { width = defaultWidth }
                    .help("끌어서 너비 조절 · 더블클릭하면 원래 너비")
            }
            .zIndex(1)
    }
}

/// 패널 위쪽의 작은 제목
struct PanelHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

/// 어두운 패널용 버튼 모양 (마우스를 올리면 밝아짐)
struct DarkButtonStyle: ButtonStyle {
    var prominent = false
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        DarkButtonBody(configuration: configuration, prominent: prominent, selected: selected)
    }

    private struct DarkButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let selected: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(prominent || selected ? Color.white : Theme.text)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fill)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }

        private var fill: Color {
            if prominent { return Theme.accent.opacity(configuration.isPressed ? 0.7 : (hovering ? 0.95 : 0.85)) }
            if selected { return Theme.accent.opacity(0.55) }
            if configuration.isPressed { return Color.white.opacity(0.14) }
            return hovering ? Theme.hover.opacity(1.6) : Theme.raised.opacity(0.0001)
        }
    }
}

/// 투명한 부분을 보여주는 체크무늬 배경
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            var path = Path()
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    path.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
            context.fill(path, with: .color(Color(white: 0.78)))
        }
    }
}
