import Foundation

enum RelayAction: String, Codable, CaseIterable, Identifiable {
    case fastMode, newChat, continueChat, sendMessage, approve, decline, voice
    case reasoningLow, reasoningMedium, reasoningHigh
    case review, debug, refactor, explain
    case task1, task2, task3, task4, task5, task6

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fastMode: return "Fast Mode"
        case .newChat: return "New chat"
        case .continueChat: return "Continue"
        case .sendMessage: return "Send"
        case .approve: return "Approve"
        case .decline: return "Decline"
        case .voice: return "Voice"
        case .reasoningLow: return "Low"
        case .reasoningMedium: return "Medium"
        case .reasoningHigh: return "High"
        case .review: return "Review"
        case .debug: return "Debug"
        case .refactor: return "Refactor"
        case .explain: return "Explain"
        case .task1, .task2, .task3, .task4, .task5, .task6: return "Task \(rawValue.last!)"
        }
    }
    var symbol: String {
        switch self {
        case .fastMode: return "bolt.fill"
        case .newChat: return "plus"
        case .continueChat: return "arrow.triangle.branch"
        case .sendMessage: return "arrow.up"
        case .approve: return "checkmark"
        case .decline: return "xmark"
        case .voice: return "mic.fill"
        case .review: return "doc.text.magnifyingglass"
        case .debug: return "ladybug"
        case .refactor: return "arrow.triangle.2.circlepath"
        case .explain: return "text.bubble"
        default: return "circle.grid.2x2"
        }
    }
    static let tasks: [Self] = [.task1, .task2, .task3, .task4, .task5, .task6]
    static let workflows: [Self] = [.review, .debug, .refactor, .explain]
    static let reasoning: [Self] = [.reasoningLow, .reasoningMedium, .reasoningHigh]
    // Approval controls require a structured request ID and exact command preview.
    // Never map a generic approval button through Accessibility.
    var requiresStructuredIntegration: Bool { self == .approve || self == .decline }
}

struct ControlState: Codable, Equatable {
    var enabled: Bool
    var value: Bool? = nil
    var reason: String? = nil
}

struct DesktopState: Codable {
    var revision: UUID = UUID()
    var capturedAt: Date = Date()
    var appName: String = "ChatGPT / Codex"
    var target: String = "No desktop task selected"
    var controls: [String: ControlState] = [:]
    var taskTitles: [String: String] = [:]
    var message: String = "Connect your Mac to begin."

    func control(_ action: RelayAction) -> ControlState {
        controls[action.rawValue] ?? ControlState(enabled: false, reason: "Not available in this desktop view.")
    }
    static var demo: Self {
        var state = Self(target: "Build the landing page", message: "Demo workspace • no desktop actions")
        for action in RelayAction.allCases { state.controls[action.rawValue] = .init(enabled: true) }
        state.controls[RelayAction.fastMode.rawValue]?.value = false
        for (action, title) in zip(RelayAction.tasks, ["Landing page", "API cleanup", "Fix navigation", "Release notes", "Test checkout", "Design tokens"]) {
            state.taskTitles[action.rawValue] = title
        }
        return state
    }
}

struct RelayCommand: Codable {
    var id: UUID = UUID()
    var action: RelayAction
    var revision: UUID
    var issuedAt: Date = Date()
    var desiredValue: Bool? = nil
}

struct RelayReply: Codable {
    var id: UUID
    var success: Bool
    var message: String
    var state: DesktopState
}

struct RelayMessage: Codable {
    enum Kind: String, Codable { case confirmed, stateRequest, state, command, reply }
    var kind: Kind
    var state: DesktopState? = nil
    var command: RelayCommand? = nil
    var reply: RelayReply? = nil
}

enum RelayFailure: Error, LocalizedError {
    case invalidHandshake, unpaired, replay, oversized, stale, unavailable(String)
    var errorDescription: String? {
        switch self {
        case .invalidHandshake: return "Pairing failed. Disconnect and try again."
        case .unpaired: return "Confirm the matching code on both devices first."
        case .replay: return "An out-of-order message was rejected. Reconnect your devices."
        case .oversized: return "The message is too large."
        case .stale: return "The desktop view changed. Refresh and try again."
        case .unavailable(let message): return message
        }
    }
}

struct CommandGate {
    private var seen: Set<UUID> = []
    mutating func validate(_ command: RelayCommand, state: DesktopState, now: Date = Date()) throws {
        guard abs(now.timeIntervalSince(command.issuedAt)) < 10,
              now.timeIntervalSince(state.capturedAt) < 5,
              command.revision == state.revision, !seen.contains(command.id) else { throw RelayFailure.stale }
        guard !command.action.requiresStructuredIntegration,
              state.control(command.action).enabled else {
            throw RelayFailure.unavailable(state.control(command.action).reason ?? "This control is unavailable.")
        }
        guard command.action != .fastMode || command.desiredValue != nil else {
            throw RelayFailure.unavailable("Fast Mode requires an explicit desired state.")
        }
        if seen.count > 1024 { seen.removeAll() }
        seen.insert(command.id)
    }
}

struct AccessibleControl: Equatable {
    var label: String
    var enabled: Bool
    var pressable: Bool
    var toggleValue: Bool?
}

enum ControlMatcher {
    static func uniqueIndex(label: String, controls: [AccessibleControl]) -> Int? {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let matches = controls.indices.filter { controls[$0].label == label && controls[$0].enabled && controls[$0].pressable }
        return matches.count == 1 ? matches[0] : nil
    }
}
