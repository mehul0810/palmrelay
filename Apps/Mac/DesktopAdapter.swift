import AppKit
import ApplicationServices
import Combine
import CryptoKit

/// A deliberately narrow, user-enabled fallback. No private OpenAI endpoints,
/// credential reads, JavaScript injection, shell execution, or global keystrokes.
@MainActor
final class DesktopAdapter: ObservableObject {
    @Published var enabled = false
    @Published var availableLabels: [String] = []
    @Published var current = DesktopState()
    @Published var mappings: [String: String] = [:]
    @Published var lastResult = "No commands received."
    private var gate = CommandGate()
    private var fingerprint: Data?
    private var targetWindow: AXUIElement?
    private var targetPID: pid_t?
    private let targetBundleIDs = ["com.openai.codex", "com.openai.chat"]

    init() {
        mappings = UserDefaults.standard.dictionary(forKey: "controlLabels") as? [String: String] ?? [
            "fastMode": "Fast mode", "newChat": "New chat", "continueChat": "Continue in a new chat",
            "sendMessage": "Send message", "voice": "Start voice chat"
        ]
    }

    func setMapping(_ action: RelayAction, label: String) {
        guard !action.requiresStructuredIntegration else { return }
        mappings[action.rawValue] = label
        UserDefaults.standard.set(mappings, forKey: "controlLabels")
        fingerprint = nil
        refresh()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private struct Snapshot {
        var window: AXUIElement
        var pid: pid_t
        var title: String
        var elements: [AXUIElement]
        var controls: [AccessibleControl]
        var digest: Data
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private func snapshot() throws -> Snapshot {
        guard enabled else { throw RelayFailure.unavailable("Enable desktop control in the Mac companion.") }
        guard AXIsProcessTrusted() else { throw RelayFailure.unavailable("Allow PalmRelay Companion in macOS Accessibility settings.") }
        let apps = targetBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard apps.count == 1, let app = apps.first else {
            throw RelayFailure.unavailable(apps.isEmpty ? "Open ChatGPT / Codex on your Mac." : "Keep only one supported desktop app open.")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let raw = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw RelayFailure.unavailable("Open a desktop chat window first.")
        }
        let window = unsafeBitCast(raw, to: AXUIElement.self)
        let title = attribute(window, kAXTitleAttribute) as? String ?? "Active desktop window"
        var queue = [window]
        var index = 0
        var elements: [AXUIElement] = []
        var controls: [AccessibleControl] = []
        var identity = [title]
        let deadline = Date().addingTimeInterval(0.8)
        while index < queue.count, index < 1500, Date() < deadline {
            let element = queue[index]
            index += 1
            let label = (attribute(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? attribute(element, kAXDescriptionAttribute) as? String ?? ""
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let value = attribute(element, kAXValueAttribute)
            // Hash visible text locally to reject a command after the task/view changes.
            // Conversation text itself is never sent to the phone or persisted.
            identity.append(role + ":" + label + ":" + (value as? String ?? ""))
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            let pressable = (actions as? [String] ?? []).contains(kAXPressAction)
            if pressable, !label.isEmpty {
                let on: Bool?
                if let number = value as? NSNumber, [0, 1].contains(number.intValue) { on = number.boolValue }
                else { on = nil }
                elements.append(element)
                controls.append(.init(label: label, enabled: (attribute(element, kAXEnabledAttribute) as? Bool) ?? false,
                                      pressable: true, toggleValue: on))
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        guard index == queue.count else { throw RelayFailure.unavailable("Desktop view is too large or slow to verify. Try a simpler window.") }
        return Snapshot(window: window, pid: app.processIdentifier, title: title, elements: elements, controls: controls,
                        digest: Data(SHA256.hash(data: Data(identity.joined(separator: "\n").utf8))))
    }

    func refresh() {
        do { apply(try snapshot()) }
        catch {
            fingerprint = nil
            targetWindow = nil
            targetPID = nil
            availableLabels = []
            current = DesktopState(message: error.localizedDescription)
        }
    }

    private func apply(_ snapshot: Snapshot) {
        var next = DesktopState(target: snapshot.title, message: "Controls reflect the current desktop view.")
        if fingerprint == snapshot.digest, targetPID == snapshot.pid, let targetWindow,
           CFEqual(targetWindow, snapshot.window) { next.revision = current.revision }
        fingerprint = snapshot.digest
        targetWindow = snapshot.window
        targetPID = snapshot.pid
        availableLabels = Array(Set(snapshot.controls.map(\.label))).sorted()
        for action in RelayAction.allCases {
            let label = mappings[action.rawValue] ?? ""
            var control = ControlState(enabled: false, reason: "Assign a visible control in the Mac companion.")
            if let index = ControlMatcher.uniqueIndex(label: label, controls: snapshot.controls) {
                control = .init(enabled: true, value: snapshot.controls[index].toggleValue)
                if action == .fastMode && control.value == nil {
                    control = .init(enabled: false, reason: "Desktop does not expose a readable Fast Mode state. No blind toggles.")
                }
            } else if !label.isEmpty { control.reason = "\(label) is missing, disabled, or ambiguous in the current view." }
            if action.requiresStructuredIntegration {
                control = .init(enabled: false, reason: "Approval needs an exact request and command preview. Use the desktop for now.")
            }
            next.controls[action.rawValue] = control
            if RelayAction.tasks.contains(action), !label.isEmpty { next.taskTitles[action.rawValue] = label }
        }
        current = next
    }

    func execute(_ command: RelayCommand) async -> RelayReply {
        do {
            let before = try snapshot()
            guard fingerprint == before.digest, targetPID == before.pid, let targetWindow,
                  CFEqual(targetWindow, before.window) else { throw RelayFailure.stale }
            try gate.validate(command, state: current)
            guard let index = ControlMatcher.uniqueIndex(label: mappings[command.action.rawValue] ?? "", controls: before.controls) else {
                throw RelayFailure.unavailable("The control is no longer available.")
            }
            if command.action == .fastMode && before.controls[index].toggleValue == command.desiredValue {
                apply(before)
                return reply(command, success: true, message: "Fast Mode is already \(command.desiredValue == true ? "on" : "off").")
            }
            guard AXUIElementPerformAction(before.elements[index], kAXPressAction as CFString) == .success else {
                throw RelayFailure.unavailable("The desktop did not accept this action.")
            }
            try await Task.sleep(for: .milliseconds(250))
            refresh()
            if command.action == .fastMode {
                guard current.control(.fastMode).value == command.desiredValue else {
                    throw RelayFailure.unavailable("Action sent, but Fast Mode could not be verified. Check the Mac before trying again.")
                }
                return reply(command, success: true, message: "Fast Mode \(command.desiredValue == true ? "on" : "off") • verified on Mac")
            }
            return reply(command, success: true, message: "\(command.action.title) pressed on Mac. Check the desktop result.")
        } catch {
            refresh()
            return reply(command, success: false, message: error.localizedDescription)
        }
    }

    private func reply(_ command: RelayCommand, success: Bool, message: String) -> RelayReply {
        lastResult = message
        return .init(id: command.id, success: success, message: message, state: current)
    }
}
