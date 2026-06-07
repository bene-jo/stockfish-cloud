import Foundation

struct StabilityTracker {
    private struct Sample: Equatable {
        var depth: Int
        var firstMoves: [String]
        var scores: [Int]
    }

    private let minimumStableDepth = 24
    private let stableSampleCount = 4
    private let settlingSampleCount = 2
    private let stableScoreWindow = 20
    private let settlingScoreWindow = 35

    private var samples: [Sample] = []
    private var lastSampleDepth = 0

    mutating func update(lines: [PrincipalVariation], expectedLineCount: Int, targetDepth: Int) -> AnalysisStability {
        guard lines.count >= expectedLineCount else {
            return .waiting
        }

        let displayedLines = Array(lines.prefix(expectedLineCount))
        let completeDepth = displayedLines
            .compactMap(\.depth)
            .min() ?? 0

        guard completeDepth > 0 else {
            return .waiting
        }

        if completeDepth > lastSampleDepth {
            lastSampleDepth = completeDepth
            samples.append(
                Sample(
                    depth: completeDepth,
                    firstMoves: displayedLines.map(firstMove),
                    scores: displayedLines.map { $0.score ?? 0 }
                )
            )

            if samples.count > stableSampleCount {
                samples.removeFirst(samples.count - stableSampleCount)
            }
        }

        guard completeDepth >= minimumStableDepth else {
            return .moving
        }

        if isStable(requiredSamples: stableSampleCount, scoreWindow: stableScoreWindow) {
            return .stable
        }

        if completeDepth >= targetDepth {
            return .maxDepth
        }

        if isStable(requiredSamples: settlingSampleCount, scoreWindow: settlingScoreWindow) {
            return .settling
        }

        return .moving
    }

    private func firstMove(for line: PrincipalVariation) -> String {
        if let san = line.san?.first, !san.isEmpty {
            return san
        }

        return line.pv.first ?? ""
    }

    private func isStable(requiredSamples: Int, scoreWindow: Int) -> Bool {
        guard samples.count >= requiredSamples else {
            return false
        }

        let recentSamples = samples.suffix(requiredSamples)
        guard let first = recentSamples.first else {
            return false
        }

        for sample in recentSamples {
            guard sample.firstMoves == first.firstMoves else {
                return false
            }

            for (index, score) in sample.scores.enumerated() {
                guard index < first.scores.count else {
                    return false
                }

                if abs(score - first.scores[index]) > scoreWindow {
                    return false
                }
            }
        }

        return true
    }
}
