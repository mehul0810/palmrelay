import SwiftUI

private let canvas = Color(red: 0.045, green: 0.065, blue: 0.075)
private let panel = Color(red: 0.085, green: 0.105, blue: 0.12)
private let mint = Color(red: 0.68, green: 0.96, blue: 0.79)

struct DeckView: View {
    @ObservedObject var model: DeckModel
    @State private var showConnection = false
    @State private var showInfo = false
    @AppStorage("keepAwake") private var keepAwake = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ConnectionBadge(link: model.link, demo: model.demo) { showConnection = true }
                    if model.demo {
                        HStack {
                            Label("Demo workspace", systemImage: "sparkles").font(.caption.weight(.medium))
                            Spacer()
                            Button("Exit demo") { model.leaveDemo() }.font(.caption.bold())
                        }.foregroundStyle(mint)
                    }
                    taskGrid
                    fastMode
                    commands
                    reasoning
                    workflows
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: model.pending == nil ? "circle.dotted" : "arrow.triangle.2.circlepath")
                        Text(model.feedback).fixedSize(horizontal: false, vertical: true)
                    }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 35, alignment: .top)
                        .accessibilityIdentifier("action-feedback")
                    if !model.demo { Text(model.state.message).font(.caption2).foregroundStyle(.secondary) }
                }.padding(22).frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
            .background(canvas)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showConnection) { ConnectionView(model: model, link: model.link) }
            .sheet(isPresented: $showInfo) {
                NavigationStack {
                    Form {
                        Section("PalmRelay · Preview 0.1") {
                            Text("An independent control deck for your AI workspace.")
                            Text("Connect the Mac companion, compare the pairing codes, then enable desktop control on your Mac. No OpenAI login is required here.")
                        }
                        Section("Desk mode") {
                            Toggle("Keep screen awake", isOn: $keepAwake)
                            Text("While PalmRelay is open. Moving the app to the background disconnects your Mac.").font(.caption)
                        }
                        Section("Available controls") {
                            Text("The Mac enables only controls it can identify. Fast Mode needs a readable state; task pads and workflows need mappings in the companion.")
                            Text("Approval buttons, live task statuses, and push-to-talk are not connected in this preview. Voice maps to a desktop voice button, using the Mac microphone.")
                        }
                        Section { Text("Independent software. Not affiliated with or endorsed by OpenAI or Work Louder.").font(.caption) }
                    }.navigationTitle("About your deck")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInfo = false } } }
                }.presentationDetents([.large])
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
            .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
        }.tint(mint)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("PALMRELAY").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(mint)
                Text("Within reach.").font(.system(size: 32, weight: .semibold, design: .rounded))
            }
            Spacer()
            Button { showInfo = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 48, height: 48).background(panel, in: Circle())
            }.accessibilityLabel("Deck settings")
        }
    }

    private func sectionLabel(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).tracking(1.3)
            Spacer()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var taskGrid: some View {
        VStack(spacing: 12) {
            sectionLabel("YOUR TASKS", detail: model.demo ? "6 assigned" : "Mapped on your Mac")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(RelayAction.tasks.enumerated()), id: \.element) { index, action in
                    let selected = model.demo && model.selectedTask == action
                    Button { model.perform(action) } label: {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                Text(String(format: "%02d", index + 1)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Spacer()
                                Circle().fill(selected ? mint : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                            }
                            Text(model.state.taskTitles[action.rawValue] ?? "Unassigned")
                                .font(.system(size: 13, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                            Text(selected ? "Selected · demo" : model.demo ? "Demo task" : "Status unavailable")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(selected ? mint : .secondary)
                        }.padding(13).background(selected ? mint.opacity(0.09) : panel, in: RoundedRectangle(cornerRadius: 19))
                            .overlay(RoundedRectangle(cornerRadius: 19).stroke(selected ? mint.opacity(0.7) : .white.opacity(0.07), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(model.pending != nil)
                        .accessibilityLabel("Task \(index + 1), \(model.state.taskTitles[action.rawValue] ?? "unassigned")")
                }
            }
        }
    }

    private var fastMode: some View {
        let state = model.state.control(.fastMode)
        let on = state.value == true
        return Button { model.perform(.fastMode) } label: {
            HStack(spacing: 16) {
                Image(systemName: "bolt.fill").font(.system(size: 29)).frame(width: 56, height: 56)
                    .background(.black.opacity(on ? 0.1 : 0.2), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Fast Mode").font(.title2.weight(.semibold))
                    Text(model.pending != nil ? "Waiting for Mac…" : on ? "A little more momentum." : state.enabled ? "Pick up the pace." : "Connect a readable desktop control.")
                        .font(.caption).opacity(0.75)
                }
                Spacer(minLength: 0)
                Text(state.value.map { $0 ? "ON" : "OFF" } ?? "—")
                    .font(.caption.monospaced().bold()).padding(.horizontal, 11).padding(.vertical, 8)
                    .background(.black.opacity(0.1), in: Capsule())
            }.padding(18).foregroundStyle(on ? canvas : mint)
                .background(on ? mint : mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(mint.opacity(on ? 0 : 0.35), lineWidth: 1))
        }.buttonStyle(.plain).disabled(model.pending != nil)
            .accessibilityLabel("Fast Mode").accessibilityValue(state.value.map { $0 ? "On" : "Off" } ?? "Unavailable")
            .accessibilityHint(state.enabled ? "Change Fast Mode on your Mac" : state.reason ?? "Unavailable")
            .accessibilityIdentifier("fast-mode")
    }

    private var commands: some View {
        VStack(spacing: 12) {
            sectionLabel("COMMANDS", detail: "One tap away")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([RelayAction.newChat, .continueChat, .sendMessage, .approve, .decline, .voice]) { action in
                    controlPad(action)
                }
            }
        }
    }

    private func controlPad(_ action: RelayAction) -> some View {
        let available = model.state.control(action).enabled
        return Button { model.perform(action) } label: {
            VStack(spacing: 10) {
                Image(systemName: action.symbol).font(.system(size: 21, weight: .medium))
                Text(action.title).font(.caption.weight(.medium))
                if !available { Text("Unavailable").font(.system(size: 9)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, minHeight: 96).foregroundStyle(available ? .white : .secondary)
                .background(panel, in: RoundedRectangle(cornerRadius: 19))
        }.buttonStyle(.plain).disabled(model.pending != nil)
            .accessibilityHint(available ? "Control your desktop" : model.state.control(action).reason ?? "Unavailable")
    }

    private var reasoning: some View {
        VStack(spacing: 13) {
            sectionLabel("REASONING", detail: model.demo ? "Demo selection" : "Mapped desktop controls")
            HStack(spacing: 6) {
                ForEach(RelayAction.reasoning) { action in
                    Button { model.perform(action) } label: {
                        Text(action.title).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(model.demo && model.selectedReasoning == action ? mint.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(model.demo && model.selectedReasoning == action ? mint : .secondary)
                    }.buttonStyle(.plain).disabled(model.pending != nil)
                }
            }.padding(5).background(panel, in: RoundedRectangle(cornerRadius: 17))
        }
    }

    private var workflows: some View {
        VStack(spacing: 12) {
            sectionLabel("WORKFLOWS", detail: "Make it a habit")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(RelayAction.workflows) { action in
                    Button { model.perform(action) } label: {
                        HStack {
                            Image(systemName: action.symbol).foregroundStyle(mint)
                            Text(action.title).font(.subheadline)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                        }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 15))
                    }.buttonStyle(.plain).disabled(model.pending != nil)
                }
            }
        }
    }
}

private struct ConnectionBadge: View {
    @ObservedObject var link: PeerLink
    var demo: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "laptopcomputer").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(demo ? "Explore the control deck" : link.peerName ?? "Connect your Mac").font(.subheadline.weight(.medium))
                    Text(demo ? "Demo · no device connected" : link.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(link.paired ? mint : .secondary).frame(width: 7, height: 7)
                Image(systemName: "chevron.right").font(.caption2)
            }.padding(15).background(panel, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain).accessibilityIdentifier("connect-mac")
    }
}

struct ConnectionView: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var link: PeerLink
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("A little closer to your desktop.", systemImage: "laptopcomputer.and.iphone").font(.headline)
                    Text("Open PalmRelay Companion on your Mac and choose Start pairing. Keep both devices nearby with Wi-Fi enabled.")
                        .foregroundStyle(.secondary)
                }
                Section("Connection") {
                    Text(link.status)
                    if let code = link.code {
                        Text(code).font(.system(size: 32, weight: .semibold, design: .monospaced))
                        Text("Compare this code with the Mac. Confirm on both screens only if they match.")
                        Button(link.confirmed ? "Waiting for your Mac…" : "Codes match") { link.confirmPairing() }.disabled(link.confirmed)
                        Button("Reject pairing", role: .destructive) { model.disconnect() }
                    } else if link.paired {
                        Label("Encrypted connection ready", systemImage: "lock.shield")
                        Button("Open control deck") { dismiss() }
                    } else if link.peerName == nil {
                        ForEach(link.nearby, id: \.self) { peer in
                            Button { link.connect(peer) } label: { Label(peer.displayName, systemImage: "laptopcomputer") }
                        }
                        if link.nearby.isEmpty && link.running { Text("No Macs found yet. Check Local Network permission on both devices.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Button(link.running ? "Disconnect" : "Find my Mac") {
                        if link.running { model.disconnect() }
                        else { model.leaveDemo(); link.start() }
                    }
                }
                Section {
                    Button("Explore demo controls") { model.enterDemo(); dismiss() }.accessibilityIdentifier("enter-demo")
                    Text("Demo controls never send commands to your Mac.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Connect your Mac")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(mint)
    }
}
