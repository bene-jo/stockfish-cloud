import SwiftUI

struct NewPositionView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Position")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 12) {
                TextField("FEN", text: $store.newFEN, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)

                SliderRow(
                    title: "Max Depth",
                    value: $store.newTargetDepth,
                    range: 10...80,
                    step: 5
                )

                SliderRow(
                    title: "Lines",
                    value: $store.newLineCount,
                    range: 1...5,
                    step: 1
                )

                Button {
                    store.startAnalysis()
                } label: {
                    Text("Start Analysis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.canStartAnalysis)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
            Slider(value: $value, in: range, step: step)
                .frame(width: 150)
        }
    }
}
