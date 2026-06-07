import SwiftUI

struct PositionsListView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            List(selection: $store.selectedPositionId) {
                ForEach(store.positions) { position in
                    PositionRow(position: position)
                        .tag(position.id)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if store.positions.isEmpty {
                    ContentUnavailableView(
                        "No Positions",
                        systemImage: "text.badge.plus",
                        description: Text("Start a new analysis above.")
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PositionRow: View {
    var position: AnalysisPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(position.isRunning ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(position.title)
                    .lineLimit(1)
            }

            HStack {
                Text("Depth \(position.currentDepth)")
                Spacer()
                Text(position.stability.label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
