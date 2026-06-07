import Foundation

enum PositionStatus: String, Codable {
    case running
    case completed
    case failed
}

struct AnalysisParameters: Codable, Equatable {
    var threads: Int
    var hashMb: Int
    var multipv: Int
    var depth: Int?
    var movetimeMs: Int?
}

struct PrincipalVariation: Codable, Equatable, Identifiable {
    var multipv: Int
    var depth: Int?
    var scoreType: String?
    var score: Int?
    var pv: [String]
    var nodes: Int?
    var nps: Int?

    var id: Int { multipv }
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
    var bestmove: String?
    var ponder: String?
    var lines: [PrincipalVariation]
    var updatedLine: PrincipalVariation?
}
