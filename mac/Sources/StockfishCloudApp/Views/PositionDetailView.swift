import SwiftUI

struct PositionDetailView: View {
    @Bindable var store: AppStore

    var body: some View {
        Group {
            if let position = store.selectedPosition {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(for: position)
                        MetricsView(position: position)
                        StabilityReasonView(position: position)
                        TopLinesView(lines: position.lines)
                        EngineMetadataView(position: position)

                        if let errorMessage = position.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                    .padding(40)
                }
            } else {
                ContentUnavailableView(
                    "No Position Selected",
                    systemImage: "scope",
                    description: Text("Start an analysis from the left pane.")
                )
            }
        }
        .navigationTitle("Stockfish Cloud")
    }

    private func header(for position: AnalysisPosition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(position.title)
                        .font(.title2.weight(.semibold))
                    Text(position.fen)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()

                Button(role: .destructive) {
                    Task { await store.stopSelectedPosition() }
                } label: {
                    Text("Stop Analysis")
                }
                .disabled(position.status != .running)
            }

            Divider()
        }
    }
}

private struct MetricsView: View {
    var position: AnalysisPosition

    var body: some View {
        HStack(spacing: 0) {
            MetricColumn(title: "Depth") {
                Text("\(position.currentDepth)")
            }

            Divider()
                .padding(.horizontal, 22)

            MetricColumn(title: "Stability") {
                StabilityBadge(stability: position.stability)
            }

            Divider()
                .padding(.horizontal, 22)

            MetricColumn(title: "Time Running") {
                Text(AppFormatters.milliseconds(position.elapsedMs))
            }

            Divider()
                .padding(.horizontal, 22)

            MetricColumn(title: "Nodes/sec") {
                Text(AppFormatters.compactNumber(position.nps))
            }
        }
        .font(.title3)
        .monospacedDigit()
    }
}

private struct StabilityBadge: View {
    var stability: AnalysisStability

    var body: some View {
        Text(stability.label)
            .font(.callout.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundStyle, in: Capsule())
    }

    private var foregroundStyle: Color {
        switch stability {
        case .stable:
            return .green
        case .settling:
            return .orange
        case .unstable:
            return .secondary
        }
    }

    private var backgroundStyle: Color {
        switch stability {
        case .stable:
            return .green.opacity(0.12)
        case .settling:
            return .orange.opacity(0.12)
        case .unstable:
            return .secondary.opacity(0.10)
        }
    }
}

private struct StabilityReasonView: View {
    var position: AnalysisPosition

    var body: some View {
        if position.stability != .stable {
            Label(position.stabilityReason, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MetricColumn<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            content
        }
        .frame(minWidth: 140)
    }
}

private struct EngineMetadataView: View {
    var position: AnalysisPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    MetadataLabel("Version")
                    MetadataValue(engineName)
                    MetadataLabel("NNUE")
                    MetadataValue(nnueLabel)
                }

                GridRow {
                    MetadataLabel("Threads")
                    MetadataValue("\(position.parameters.threads)")
                    MetadataLabel("Lines")
                    MetadataValue("\(position.parameters.multipv)")
                }

                GridRow {
                    MetadataLabel("Target")
                    MetadataValue(targetLabel)
                    EmptyView()
                    EmptyView()
                }
            }
            .font(.callout)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var engineName: String {
        if let name = position.engine?.name, !name.isEmpty {
            return name
        }

        if let version = position.engine?.version, !version.isEmpty {
            return "Stockfish \(version)"
        }

        return "Stockfish"
    }

    private var nnueLabel: String {
        guard position.engine?.nnue == true else {
            return "-"
        }

        return position.engine?.evalFile ?? "On"
    }

    private var targetLabel: String {
        if let depth = position.parameters.depth {
            return "Stable / Depth \(depth)"
        }

        if let movetimeMs = position.parameters.movetimeMs {
            return AppFormatters.milliseconds(movetimeMs)
        }

        return "-"
    }
}

private struct MetadataLabel: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
    }
}

private struct MetadataValue: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }
}
