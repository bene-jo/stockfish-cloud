import Foundation

enum AppFormatters {
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return "\(minutes)m \(remainingSeconds)s"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }

    static func milliseconds(_ milliseconds: Int) -> String {
        duration(milliseconds / 1_000)
    }

    static func euros(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return String(format: "€%.3f", value)
    }

    static func compactNumber(_ value: Int?) -> String {
        guard let value else {
            return "-"
        }

        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }

        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }

        return "\(value)"
    }

    static func evaluation(scoreType: String?, score: Int?) -> String {
        guard let scoreType, let score else {
            return "-"
        }

        if scoreType == "mate" {
            return "M\(score)"
        }

        let pawns = Double(score) / 100
        return String(format: "%+.2f", pawns)
    }
}

enum PositionTitleResolver {
    static func title(for fen: String) -> String {
        if fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" {
            return "Starting Position"
        }

        return snippet(for: fen)
    }

    static func snippet(for fen: String) -> String {
        if fen.count <= 42 {
            return fen
        }

        return String(fen.prefix(42)) + "..."
    }
}
