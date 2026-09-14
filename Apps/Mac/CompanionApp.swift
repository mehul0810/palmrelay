import SwiftUI

@main
struct CompanionApp: App {
    @StateObject private var model = CompanionModel()
    var body: some Scene {
        WindowGroup("PalmRelay Companion") { CompanionView(model: model).frame(minWidth: 620, minHeight: 640) }
        MenuBarExtra("PalmRelay", systemImage: "rectangle.grid.2x2") {
            Text(model.link.status)
            Button("Disconnect") { model.stop() }
            Button("Quit PalmRelay") { model.stop(); NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class CompanionModel: ObservableObject {
    let link = PeerLink(host: true)
    let adapter = DesktopAdapter()
    private var executing = false
    init() {
        link.onMessage = { [weak self] message in
            guard let self else { return }
            switch message.kind {
            case .stateRequest:
                guard !self.executing else { return }
                self.adapter.refresh()
                self.link.send(.init(kind: .state, state: self.adapter.current))
            case .command:
                guard let command = message.command, !self.executing else { return }
                self.executing = true
                Task { @MainActor in
                    let result = await self.adapter.execute(command)
                    self.link.send(.init(kind: .reply, reply: result))
                    self.executing = false
                }
            default: break
            }
        }
        link.onDisconnect = { [weak self] in self?.adapter.enabled = false }
    }
    func stop() { adapter.enabled = false; link.stop() }
}

struct CompanionView: View {
    @ObservedObject var model: CompanionModel
    var body: some View { CompanionContent(link: model.link, adapter: model.adapter) }
}

struct CompanionContent: View {
    @ObservedObject var link: PeerLink
    @ObservedObject var adapter: DesktopAdapter
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.grid.2x2.fill").font(.largeTitle).foregroundStyle(.mint)
                    VStack(alignment: .leading) {
                        Text("PalmRelay").font(.largeTitle.bold())
                        Text("Your desktop, within reach.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("PREVIEW 0.1").font(.caption.monospaced()).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            Section("1 · Connect your iPhone") {
                LabeledContent("Connection", value: link.status)
                if let peer = link.peerName { LabeledContent("Device", value: peer) }
                if let code = link.code {
                    Text(code).font(.system(size: 32, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Text("Confirm only if this exact code appears on your iPhone. Device names alone are not trusted.")
                    HStack {
                        Button(link.confirmed ? "Waiting for iPhone…" : "Codes match") { link.confirmPairing() }.disabled(link.confirmed)
                        Button("Reject") { link.stop() }
                    }
                }
                Button(link.running ? "Disconnect & stop discovery" : "Start pairing") {
                    if link.running { link.stop() } else { link.start() }
                }
                Text("Local connection only. Pairing expires when disconnected. No OpenAI login or cloud relay.").font(.caption).foregroundStyle(.secondary)
            }
            Section("2 · Allow desktop controls") {
                Button("Request Accessibility access") { adapter.requestAccessibility() }
                Toggle("Enable control of ChatGPT / Codex", isOn: $adapter.enabled)
                    .onChange(of: adapter.enabled) { _, _ in adapter.refresh() }
                Text("PalmRelay reads the focused window of the supported desktop app and presses only the exact controls you map below. You can stop access here at any time.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(adapter.current.message)
                LabeledContent("Target window", value: adapter.current.target)
                Button("Refresh visible controls") { adapter.refresh() }
            }
            Section("3 · Map your control deck") {
                Text("Select exact visible button labels. Fast Mode also requires a readable on/off state. Missing or duplicate labels remain unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(RelayAction.allCases.filter { !$0.requiresStructuredIntegration }) { action in
                    VStack(alignment: .leading, spacing: 3) {
                        Picker(action.title, selection: Binding(get: { adapter.mappings[action.rawValue] ?? "" },
                                                               set: { adapter.setMapping(action, label: $0) })) {
                            Text("Unassigned").tag("")
                            ForEach(Array(Set(adapter.availableLabels + [adapter.mappings[action.rawValue] ?? ""])).filter { !$0.isEmpty }.sorted(), id: \.self) { label in
                                Text(label).tag(label)
                            }
                        }
                        if let reason = adapter.current.control(action).reason { Text(reason).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Integration status") {
                Text("Experimental Accessibility adapter — not yet verified against your desktop app version.")
                Text("Approve / Decline are unavailable until a structured approval integration is implemented. Task status colors, automatic task discovery, continuous reasoning adjustment, and push-to-talk are not yet connected. Voice can map a visible start-voice button.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Last action", value: adapter.lastResult)
            }
        }.formStyle(.grouped)
    }
}
