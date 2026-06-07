import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    var server = ServerState.offline
    var positions: [AnalysisPosition] = []
    var selectedPositionId: String?
    var newFEN = ""
    var newLineCount = 3.0
    var statusMessage: String?
    var isRefreshingServer = false
    var isStartingServer = false
    var isDeletingServer = false
    var isStartingAnalysis = false

    private let cli: StockfishCloudCLI
    private let serverName = "stockfish-cloud"
    private let automaticMaxDepth = 60
    private var stabilityTrackers: [String: StabilityTracker] = [:]
    private var autoStopRequests: Set<String> = []

    init(cli: StockfishCloudCLI = StockfishCloudCLI()) {
        self.cli = cli
        self.server.server = serverName
    }

    var selectedPosition: AnalysisPosition? {
        guard let selectedPositionId else {
            return positions.first
        }

        return positions.first { $0.id == selectedPositionId }
    }

    var hasRunningPosition: Bool {
        positions.contains { $0.status == .running } || isStartingAnalysis
    }

    var canStartAnalysis: Bool {
        !newFEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            server.running &&
            !hasRunningPosition
    }

    var newPositionButtonTitle: String {
        if hasRunningPosition {
            return "Analysis Running"
        }

        return "Start Analysis"
    }

    func refreshServerStatus() async {
        isRefreshingServer = true
        defer { isRefreshingServer = false }

        do {
            server = try await cli.status(server: serverName)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func startServer() async {
        isStartingServer = true
        defer { isStartingServer = false }

        do {
            try await cli.startServer(server: serverName)
            await refreshServerStatus()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteServer() async {
        isDeletingServer = true
        defer { isDeletingServer = false }

        do {
            try await cli.deleteServer(server: serverName)
            await refreshServerStatus()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func startAnalysis() {
        guard canStartAnalysis else {
            return
        }

        let fen = newFEN.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = "position-\(UUID().uuidString.prefix(8).lowercased())"
        let targetDepth = automaticMaxDepth
        let lineCount = Int(newLineCount)
        let parameters = AnalysisParameters(
            threads: 8,
            hashMb: 4096,
            multipv: lineCount,
            depth: targetDepth,
            movetimeMs: nil
        )
        let position = AnalysisPosition(
            id: id,
            title: PositionTitleResolver.title(for: fen),
            fen: fen,
            status: .running,
            currentDepth: 0,
            targetDepth: targetDepth,
            elapsedMs: 0,
            nps: nil,
            lines: [],
            parameters: parameters,
            engine: nil,
            stability: .waiting,
            errorMessage: nil
        )

        stabilityTrackers[id] = StabilityTracker()
        positions.insert(position, at: 0)
        selectedPositionId = id
        newFEN = ""

        Task {
            await runPosition(id: id, fen: fen, targetDepth: targetDepth, lineCount: lineCount)
        }
    }

    func stopSelectedPosition() async {
        guard let position = selectedPosition, position.status == .running else {
            return
        }

        do {
            try await cli.stopPosition(server: serverName, positionId: position.id)
        } catch {
            updatePosition(id: position.id) { position in
                position.errorMessage = error.localizedDescription
            }
        }
    }

    private func runPosition(id: String, fen: String, targetDepth: Int, lineCount: Int) async {
        isStartingAnalysis = true
        defer { isStartingAnalysis = false }

        updatePosition(id: id) { position in
            position.status = .running
            position.targetDepth = targetDepth
            position.parameters.depth = targetDepth
            position.stability = .waiting
            position.errorMessage = nil
        }
        autoStopRequests.remove(id)

        do {
            for try await event in cli.streamPosition(
                server: serverName,
                positionId: id,
                fen: fen,
                depth: targetDepth,
                lines: lineCount
            ) {
                let stability = apply(event: event, to: id)
                if stability == .stable && autoStopRequests.insert(id).inserted {
                    try? await cli.stopPosition(server: serverName, positionId: id)
                }
            }
        } catch {
            updatePosition(id: id) { position in
                position.status = .failed
                position.errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(event: AnalysisStateEvent, to id: String) -> AnalysisStability {
        let targetDepth = event.targetDepth ?? automaticMaxDepth
        let expectedLineCount = event.parameters.multipv
        var tracker = stabilityTrackers[id] ?? StabilityTracker()
        let stability = tracker.update(
            lines: event.lines,
            expectedLineCount: expectedLineCount,
            targetDepth: targetDepth
        )
        stabilityTrackers[id] = tracker

        updatePosition(id: id) { position in
            position.status = event.status
            position.elapsedMs = event.elapsedMs
            position.currentDepth = event.currentDepth ?? position.currentDepth
            position.targetDepth = event.targetDepth ?? position.targetDepth
            position.lines = event.lines
            position.nps = event.lines.first?.nps
            position.parameters = event.parameters
            position.engine = event.engine ?? position.engine
            position.stability = stability
            position.errorMessage = nil
        }

        return stability
    }

    private func updatePosition(id: String, mutate: (inout AnalysisPosition) -> Void) {
        guard let index = positions.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&positions[index])
    }
}
