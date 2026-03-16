import Foundation

/// Identifies which coding agent produced an event or owns a session.
enum AgentSource: String, Codable, CaseIterable {
    case claudeCode = "claude_code"
    case copilot = "copilot"
    case unknown = "unknown"

    /// Human-readable label for UI display.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .copilot: "Copilot CLI"
        case .unknown: "Agent"
        }
    }

    /// SF Symbol for compact badges.
    var sfSymbol: String {
        switch self {
        case .claudeCode: "c.circle.fill"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .unknown: "questionmark.circle"
        }
    }

    /// Accent color name (resolved by views into actual Color values).
    var accentColorName: String {
        switch self {
        case .claudeCode: "orange"
        case .copilot: "blue"
        case .unknown: "gray"
        }
    }

    /// Parse from the raw `source` string on a hook event.
    /// Falls back to `.unknown` for nil or unrecognised values.
    init(rawSource: String?) {
        guard let raw = rawSource?.lowercased() else {
            self = .unknown
            return
        }
        switch raw {
        case "claude_code", "claude-code", "claudecode": self = .claudeCode
        case "copilot", "copilot_cli", "copilot-cli", "github_copilot": self = .copilot
        default: self = .unknown
        }
    }
}
