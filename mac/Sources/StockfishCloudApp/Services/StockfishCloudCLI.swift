import Foundation

enum StockfishCloudCLIError: LocalizedError {
    case missingExecutable(URL)
    case processFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let url):
            return "Could not find stockfish-cloud CLI at \(url.path)."
        case .processFailed(let message):
            return message
        case .invalidOutput(let output):
            return "Could not parse CLI output: \(output)"
        }
    }
}

struct StockfishCloudCLI {
    private let projectRoot: URL

    init(projectRoot: URL = StockfishCloudCLI.defaultProjectRoot()) {
        self.projectRoot = projectRoot
    }

    static func defaultProjectRoot() -> URL {
        if let path = ProcessInfo.processInfo.environment["STOCKFISH_CLOUD_ROOT"] {
            return URL(fileURLWithPath: path)
        }

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func status(server: String) async throws -> ServerState {
        let output = try await run(arguments: ["status", "--server", server, "--json"])
        guard let data = output.data(using: .utf8) else {
            throw StockfishCloudCLIError.invalidOutput(output)
        }

        return try JSONDecoder().decode(ServerState.self, from: data)
    }

    func startServer(server: String) async throws {
        _ = try await run(arguments: [
            "start",
            "--server", server,
            "--server-type", "ccx33",
            "--location", "fsn1",
            "--worker-image", "ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest",
            "--skip-build"
        ])
    }

    func deleteServer(server: String) async throws {
        _ = try await run(arguments: ["delete", "--server", server])
    }

    func stopPosition(server: String, positionId: String) async throws {
        _ = try await run(arguments: [
            "stop-position",
            "--server", server,
            "--position-id", positionId,
            "--json"
        ])
    }

    func streamPosition(
        server: String,
        positionId: String,
        fen: String,
        depth: Int,
        lines: Int
    ) -> AsyncThrowingStream<AnalysisStateEvent, Error> {
        AsyncThrowingStream { continuation in
            let executable = cliURL()
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                continuation.finish(throwing: StockfishCloudCLIError.missingExecutable(executable))
                return
            }

            let process = Process()
            let output = Pipe()
            let error = Pipe()
            var buffer = Data()

            process.executableURL = executable
            process.currentDirectoryURL = projectRoot
            process.arguments = [
                "analyze-position",
                "--server", server,
                "--worker-image", "ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest",
                "--position-id", positionId,
                "--fen", fen,
                "--threads", "8",
                "--hash", "4096",
                "--depth", "\(depth)",
                "--lines", "\(lines)"
            ]
            process.standardOutput = output
            process.standardError = error

            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                buffer.append(data)
                while let newlineIndex = buffer.firstIndex(of: 10) {
                    let lineData = buffer[..<newlineIndex]
                    buffer.removeSubrange(...newlineIndex)

                    guard
                        let line = String(data: lineData, encoding: .utf8),
                        line.first == "{",
                        let jsonData = line.data(using: .utf8)
                    else {
                        continue
                    }

                    do {
                        let event = try JSONDecoder().decode(AnalysisStateEvent.self, from: jsonData)
                        continuation.yield(event)
                    } catch {
                        continuation.yield(with: .failure(error))
                    }
                }
            }

            process.terminationHandler = { finishedProcess in
                output.fileHandleForReading.readabilityHandler = nil

                if finishedProcess.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    let errorData = error.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: errorData, encoding: .utf8) ?? "Analysis failed."
                    continuation.finish(throwing: StockfishCloudCLIError.processFailed(message))
                }
            }

            continuation.onTermination = { _ in
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func run(arguments: [String]) async throws -> String {
        let executable = cliURL()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw StockfishCloudCLIError.missingExecutable(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let error = Pipe()

            process.executableURL = executable
            process.currentDirectoryURL = projectRoot
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error

            process.terminationHandler = { finishedProcess in
                let outputData = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = error.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: outputData, encoding: .utf8) ?? ""
                let errorText = String(data: errorData, encoding: .utf8) ?? ""

                if finishedProcess.terminationStatus == 0 {
                    continuation.resume(returning: outputText.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let message = errorText.isEmpty ? outputText : errorText
                    continuation.resume(throwing: StockfishCloudCLIError.processFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func cliURL() -> URL {
        projectRoot.appendingPathComponent("bin/stockfish-cloud")
    }
}
