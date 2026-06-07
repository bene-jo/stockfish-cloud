import Foundation

struct ServerState: Codable, Equatable {
    var server: String
    var status: String
    var running: Bool
    var serverType: String?
    var location: String?
    var createdAt: String?
    var uptimeSeconds: Int
    var hourlyRateEur: Double?
    var liveCostEur: Double?

    static let offline = ServerState(
        server: "stockfish-cloud",
        status: "offline",
        running: false,
        serverType: nil,
        location: nil,
        createdAt: nil,
        uptimeSeconds: 0,
        hourlyRateEur: nil,
        liveCostEur: 0
    )
}
