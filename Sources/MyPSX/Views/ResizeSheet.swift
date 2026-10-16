import SwiftUI

/// 크기 조절 창
struct ResizeSheet: View {
    let originalSize: CGSize
    let onApply: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var width: Int
    @State private var height: Int
    @State private var keepAspect = true

    private let maxDimension = 20_000

    init(originalSize: CGSize, onApply: @escaping (Int, Int) -> Void) {
        self.originalSize = originalSize
        self.onApply = onApply
        _width = State(initialValue: Int(originalSize.width))
        _height = State(initialValue: Int(originalSize.height))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("크기 조절").font(.headline)
            Text("원본: \(Int(originalSize.width)) × \(Int(originalSize.height)) px")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("너비")
                    TextField("너비", value: widthBinding, format: .number.grouping(.never))
                        .frame(width: 100)
                    Text("px").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("높이")
                    TextField("높이", value: heightBinding, format: .number.grouping(.never))
                        .frame(width: 100)
                    Text("px").foregroundStyle(.secondary)
                }
            }
            .textFieldStyle(.roundedBorder)

            Toggle("가로세로 비율 유지", isOn: $keepAspect)

            HStack {
                ForEach([25, 50, 75, 200], id: \.self) { percent in
                    Button("\(percent)%") { applyPercent(percent) }
                }
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("적용") {
                    onApply(width, height)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(width == Int(originalSize.width) && height == Int(originalSize.height))
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private var ratio: Double {
        originalSize.height > 0 ? originalSize.width / originalSize.height : 1
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, 1), maxDimension)
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { width },
            set: { newValue in
                width = clamp(newValue)
                if keepAspect { height = clamp(Int((Double(width) / ratio).rounded())) }
            }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { height },
            set: { newValue in
                height = clamp(newValue)
                if keepAspect { width = clamp(Int((Double(height) * ratio).rounded())) }
            }
        )
    }

    private func applyPercent(_ percent: Int) {
        width = clamp(Int((originalSize.width * Double(percent) / 100).rounded()))
        height = clamp(Int((originalSize.height * Double(percent) / 100).rounded()))
    }
}
