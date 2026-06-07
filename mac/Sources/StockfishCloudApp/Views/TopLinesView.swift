import SwiftUI

struct TopLinesView: View {
    var lines: [PrincipalVariation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Lines")
                .font(.headline)

            if lines.isEmpty {
                Text("Waiting for analysis...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        LineRow(line: line)
                        if line.id != lines.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct LineRow: View {
    var line: PrincipalVariation

    var body: some View {
        HStack(spacing: 18) {
            Text("\(line.multipv)")
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            Text(AppFormatters.evaluation(scoreType: line.scoreType, score: line.score))
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)

            Text(line.displayMoves.joined(separator: " "))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
