import SwiftUI

/// Compact pill that identifies the agent source (Claude Code / Copilot CLI).
/// Renders nothing for `.unknown` to keep the UI clean for legacy events.
struct AgentSourceBadge: View {
    let source: AgentSource
    var compact: Bool = false

    var body: some View {
        if source != .unknown {
            HStack(spacing: 3) {
                Image(systemName: source.sfSymbol)
                    .font(.system(size: compact ? 7 : 8))
                if !compact {
                    Text(source.displayName)
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .foregroundStyle(accentColor)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, 2)
            .background(accentColor.opacity(0.10), in: Capsule())
        }
    }

    private var accentColor: Color {
        switch source {
        case .claudeCode: Constants.orangePrimary
        case .copilot: .blue
        case .unknown: .gray
        }
    }
}
