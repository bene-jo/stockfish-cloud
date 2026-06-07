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
            threads: 16,
            hashMb: 24576,
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
            stability: .unstable,
            stabilityReason: "Waiting for engine output.",
            errorMessage: nil
        )

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
            position.stability = .unstable
            position.stabilityReason = "Waiting for engine output."
            position.errorMessage = nil
        }

        do {
            for try await event in cli.streamPosition(
                server: serverName,
                positionId: id,
                fen: fen,
                depth: targetDepth,
                lines: lineCount
            ) {
                apply(event: event, to: id)
            }
        } catch {
            updatePosition(id: id) { position in
                position.status = .failed
                position.errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(event: AnalysisStateEvent, to id: String) {
        updatePosition(id: id) { position in
            position.status = event.status
            position.elapsedMs = event.elapsedMs
            position.currentDepth = event.currentDepth ?? position.currentDepth
            position.targetDepth = event.targetDepth ?? position.targetDepth
            position.lines = event.lines
            position.nps = event.lines.first?.nps
            position.parameters = event.parameters
            position.engine = event.engine ?? position.engine
            position.stability = event.stability?.state ?? position.stability
            position.stabilityReason = event.stability?.reason ?? position.stabilityReason
            position.errorMessage = nil
        }
    }

    private func updatePosition(id: String, mutate: (inout AnalysisPosition) -> Void) {
        guard let index = positions.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&positions[index])
    }
}
