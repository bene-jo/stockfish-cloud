import Foundation

struct StabilityTracker {
    private struct Sample: Equatable {
        var depth: Int
        var movePrefixes: [[String]]
        var scores: [Int]
    }

    private let minimumSettlingDepth = 30
    private let minimumStableDepth = 40
    private let minimumPVMoves = 8
    private let comparedPrefixMoves = 6
    private let stableSampleCount = 8
    private let settlingSampleCount = 4
    private let stableScoreWindow = 10
    private let settlingScoreWindow = 20

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

        guard displayedLines.allSatisfy({ $0.pv.count >= minimumPVMoves && $0.score != nil }) else {
            return .moving
        }

        if completeDepth > lastSampleDepth {
            lastSampleDepth = completeDepth
            samples.append(
                Sample(
                    depth: completeDepth,
                    movePrefixes: displayedLines.map(movePrefix),
                    scores: displayedLines.compactMap(\.score)
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

        guard completeDepth >= minimumSettlingDepth else {
            return .moving
        }

        if isStable(requiredSamples: settlingSampleCount, scoreWindow: settlingScoreWindow) {
            return .settling
        }

        return .moving
    }

    private func movePrefix(for line: PrincipalVariation) -> [String] {
        Array(line.pv.prefix(comparedPrefixMoves))
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
            guard sample.movePrefixes == first.movePrefixes else {
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
