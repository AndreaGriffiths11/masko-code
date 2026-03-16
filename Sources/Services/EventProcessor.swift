import Foundation

@Observable
final class EventProcessor {
    private let eventStore: EventStore
    private let sessionStore: SessionStore
    private let notificationStore: NotificationStore
    private let notificationService: NotificationService

    init(
        eventStore: EventStore,
        sessionStore: SessionStore,
        notificationStore: NotificationStore,
        notificationService: NotificationService
    ) {
        self.eventStore = eventStore
        self.sessionStore = sessionStore
        self.notificationStore = notificationStore
        self.notificationService = notificationService
    }

    @MainActor func process(_ event: ClaudeEvent) async {
        eventStore.append(event)
        sessionStore.recordEvent(event)

        if let notification = createNotification(from: event) {
            notificationStore.append(notification)
            await notificationService.show(notification)
        }
    }

    private func createNotification(from event: ClaudeEvent) -> AppNotification? {
        guard let eventType = event.eventType else { return nil }
        let source = event.agentSource
        let agentLabel = source == .unknown ? "" : "[\(source.displayName)] "

        switch eventType {
        case .notification:
            switch event.notificationType {
            case "permission_prompt":
                return AppNotification(
                    title: "\(agentLabel)Permission Required",
                    body: event.message ?? "An agent needs your approval to proceed",
                    category: .permissionRequest,
                    priority: .urgent,
                    sessionId: event.sessionId,
                    agentSource: source
                )
            case "idle_prompt":
                return AppNotification(
                    title: "\(agentLabel)\(source.displayName) is Waiting",
                    body: event.message ?? "An agent has been idle in \(event.projectName ?? "a project")",
                    category: .idleAlert,
                    priority: .high,
                    sessionId: event.sessionId,
                    agentSource: source
                )
            case "elicitation_dialog":
                return AppNotification(
                    title: "\(agentLabel)Input Needed",
                    body: event.message ?? "An agent needs your input",
                    category: .elicitationDialog,
                    priority: .high,
                    sessionId: event.sessionId,
                    agentSource: source
                )
            default:
                return nil
            }

        case .permissionRequest:
            // For AskUserQuestion: show the actual question text
            let body: String
            if event.toolName == "AskUserQuestion",
               let input = event.toolInput,
               let questions = input["questions"]?.value as? [Any] ?? (input["questions"]?.value as? [[String: Any]]),
               let firstQ = questions.first,
               let qDict = (firstQ as? [String: Any]) ?? (firstQ as? [String: AnyCodable])?.mapValues(\.value),
               let questionText = qDict["question"] as? String {
                body = questionText
            } else {
                body = "\(source.displayName) wants to use \(event.toolName ?? "a tool") in \(event.projectName ?? "a project")"
            }
            return AppNotification(
                title: event.toolName == "AskUserQuestion" ? "\(agentLabel)Question" : "\(agentLabel)Permission Requested",
                body: body,
                category: .permissionRequest,
                priority: .high,
                sessionId: event.sessionId,
                agentSource: source
            )

        case .stop:
            return AppNotification(
                title: "\(agentLabel)Task Completed",
                body: truncate(event.lastAssistantMessage, maxLength: 100)
                    ?? "Agent finished in \(event.projectName ?? "a project")",
                category: .sessionLifecycle,
                priority: .normal,
                sessionId: event.sessionId,
                agentSource: source
            )

        case .postToolUseFailure:
            return AppNotification(
                title: "\(agentLabel)Tool Failed",
                body: "\(event.toolName ?? "A tool") failed in \(event.projectName ?? "a project")",
                category: .toolFailed,
                priority: .normal,
                sessionId: event.sessionId,
                agentSource: source
            )

        case .taskCompleted:
            return AppNotification(
                title: "\(agentLabel)Task Completed",
                body: event.taskSubject ?? "A task was completed",
                category: .taskCompleted,
                priority: .normal,
                sessionId: event.sessionId,
                agentSource: source
            )

        case .sessionStart:
            return AppNotification(
                title: "\(agentLabel)Session Started",
                body: "New \(source.displayName) session in \(event.projectName ?? "unknown project")",
                category: .sessionLifecycle,
                priority: .low,
                sessionId: event.sessionId,
                agentSource: source
            )

        case .sessionEnd:
            return AppNotification(
                title: "\(agentLabel)Session Ended",
                body: "\(source.displayName) session ended in \(event.projectName ?? "unknown project")",
                category: .sessionLifecycle,
                priority: .low,
                sessionId: event.sessionId,
                agentSource: source
            )

        case .preCompact:
            return AppNotification(
                title: "\(agentLabel)Context Compacting",
                body: "\(source.displayName) is compacting context in \(event.projectName ?? "a project")",
                category: .sessionLifecycle,
                priority: .low,
                sessionId: event.sessionId,
                agentSource: source
            )

        default:
            return nil
        }
    }

    private func truncate(_ text: String?, maxLength: Int) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}
