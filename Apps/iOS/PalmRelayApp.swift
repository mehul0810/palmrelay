import SwiftUI

@main
struct PalmRelayApp: App {
    @StateObject private var model = DeckModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            DeckView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .background { model.disconnect() }
                }
        }
    }
}

@MainActor
final class DeckModel: ObservableObject {
    let link = PeerLink(host: false)
    @Published var state = DesktopState()
    @Published var demo = false
    @Published var pending: UUID?
    @Published var feedback = "Your AI workspace, within reach."
    @Published var selectedTask: RelayAction = .task1
    @Published var selectedReasoning: RelayAction = .reasoningMedium
    private var poll: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var lastReceived: Date?

    init() {
        link.onMessage = { [weak self] message in
            guard let self else { return }
            if let state = message.state, message.kind == .state {
                self.state = state
                self.lastReceived = Date()
            }
            if let reply = message.reply, message.kind == .reply, self.pending == reply.id {
                self.timeout?.cancel()
                self.pending = nil
                self.state = reply.state
                self.lastReceived = Date()
                self.feedback = reply.message
                UINotificationFeedbackGenerator().notificationOccurred(reply.success ? .success : .error)
            }
        }
        link.onDisconnect = { [weak self] in
            guard let self, !self.demo else { return }
            self.state = DesktopState()
            self.lastReceived = nil
            self.pending = nil
            self.timeout?.cancel()
        }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                if self.link.paired && !self.demo && self.pending == nil {
                    if let received = self.lastReceived, Date().timeIntervalSince(received) > 5 {
                        self.state = DesktopState(message: "Waiting for a fresh desktop update…")
                    }
                    self.link.send(.init(kind: .stateRequest))
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--demo") { enterDemo() }
    }

    func enterDemo() {
        link.stop()
        demo = true
        state = .demo
        pending = nil
        feedback = "Demo only — your desktop is not connected."
    }

    func disconnect() {
        timeout?.cancel()
        pending = nil
        link.stop()
        if !demo { state = DesktopState(); feedback = "Disconnected. Pair again to resume." }
    }

    func leaveDemo() {
        demo = false
        state = DesktopState()
        feedback = "Connect your Mac to begin."
    }

    func perform(_ action: RelayAction) {
        guard pending == nil else { return }
        let capability = state.control(action)
        guard capability.enabled else {
            feedback = capability.reason ?? "This control is unavailable."
            return
        }
        if demo {
            if action == .fastMode { state.controls[action.rawValue]?.value = !(capability.value ?? false) }
            if RelayAction.tasks.contains(action) { selectedTask = action; state.target = state.taskTitles[action.rawValue] ?? action.title }
            if RelayAction.reasoning.contains(action) { selectedReasoning = action }
            feedback = "Demo · \(action.title)\(action == .fastMode ? (state.control(.fastMode).value == true ? " on" : " off") : " tapped")"
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }
        guard link.paired, let received = lastReceived, Date().timeIntervalSince(received) < 5 else {
            feedback = "Waiting for a fresh desktop connection."
            return
        }
        let command = RelayCommand(action: action, revision: state.revision,
                                   desiredValue: action == .fastMode ? !(capability.value ?? false) : nil)
        pending = command.id
        feedback = "Waiting for your Mac…"
        link.send(.init(kind: .command, command: command))
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.pending == command.id else { return }
            self.pending = nil
            self.state = DesktopState(message: "Refresh the desktop connection before another action.")
            self.lastReceived = nil
            self.feedback = "No acknowledgement. Check your Mac; this action will not be retried automatically."
        }
    }
}
