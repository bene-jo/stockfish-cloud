import Foundation

enum PositionStatus: String, Codable {
    case running
    case completed
    case failed
}

enum AnalysisStability: String, Codable {
    case waiting
    case moving
    case settling
    case stable
    case maxDepth

    var label: String {
        switch self {
        case .waiting:
            return "Waiting"
        case .moving:
            return "Still Moving"
        case .settling:
            return "Settling"
        case .stable:
            return "Stable"
        case .maxDepth:
            return "Max Depth"
        }
    }
}

struct AnalysisParameters: Codable, Equatable {
    var threads: Int
    var hashMb: Int
    var multipv: Int
    var depth: Int?
    var movetimeMs: Int?
}

struct EngineMetadata: Codable, Equatable {
    var name: String?
    var version: String?
    var evalFile: String?
    var nnue: Bool?
}

struct PrincipalVariation: Codable, Equatable, Identifiable {
    var multipv: Int
    var depth: Int?
    var scoreType: String?
    var score: Int?
    var rawScore: Int?
    var pv: [String]
    var san: [String]?
    var nodes: Int?
    var nps: Int?

    var id: Int { multipv }

    var displayMoves: [String] {
        guard let san, !san.isEmpty else {
            return pv
        }

        return san
    }
}

struct AnalysisPosition: Identifiable, Equatable {
    var id: String
    var title: String
    var fen: String
    var status: PositionStatus
    var currentDepth: Int
    var targetDepth: Int
    var elapsedMs: Int
    var nps: Int?
    var lines: [PrincipalVariation]
    var parameters: AnalysisParameters
    var engine: EngineMetadata?
    var stability: AnalysisStability
    var errorMessage: String?

    var isRunning: Bool {
        status == .running
    }
}

struct AnalysisStateEvent: Codable {
    var event: String
    var positionId: String?
    var status: PositionStatus
    var fen: String
    var elapsedMs: Int
    var currentDepth: Int?
    var targetDepth: Int?
    var parameters: AnalysisParameters
    var engine: EngineMetadata?
    var bestmove: String?
    var ponder: String?
    var lines: [PrincipalVariation]
    var updatedLine: PrincipalVariation?
}
