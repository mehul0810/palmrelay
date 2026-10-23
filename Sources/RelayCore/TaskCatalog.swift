import Foundation

/// Summary-only values from the public App Server protocol. No transcript paths,
/// credentials, transport, or desktop control capabilities are represented here.
struct DiscoveredTask: Decodable, Equatable, Identifiable {
    let id: String
    let name: String?
    let status: TaskRuntimeStatus

    var displayName: String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Untitled task"
        }
        return name
    }
}

struct TaskRuntimeStatus: Decodable, Equatable {
    let type: String
    let activeFlags: [String]?

    var label: String {
        switch type {
        case "notLoaded": return "Not loaded"
        case "idle": return "Idle"
        case "systemError": return "System error"
        case "active":
            if activeFlags?.contains("waitingOnApproval") == true { return "Waiting for approval" }
            if activeFlags?.contains("waitingOnUserInput") == true { return "Waiting for input" }
            return "Active"
        default: return "Unknown status"
        }
    }
}

/// Decode the JSON-RPC result, not the envelope. The transport must correlate
/// responses with the exact request before passing them to the catalog.
struct TaskListPage: Decodable {
    let data: [DiscoveredTask]
    let nextCursor: String?
}

struct TaskStatusChange: Decodable {
    let threadId: String
    let status: TaskRuntimeStatus
}

struct TaskCatalog {
    enum Phase: Equatable { case disconnected, loading, complete }
    struct Request: Equatable {
        fileprivate let generation: UUID
        let cursor: String?
    }
    struct Entry: Equatable, Identifiable {
        var task: DiscoveredTask
        var observedAt: Date
        var id: String { task.id }
    }

    private(set) var phase: Phase = .disconnected
    private(set) var entries: [Entry] = []
    private(set) var nextRequest: Request?
    private var generation = UUID()
    private var consumedCursors: Set<String> = []
    private var eventUpdates: [String: (TaskRuntimeStatus, Date)] = [:]

    /// Start a fresh snapshot. Old connection/request results cannot repopulate it.
    mutating func refresh() -> Request {
        generation = UUID()
        entries = []
        consumedCursors = []
        eventUpdates = [:]
        phase = .loading
        let request = Request(generation: generation, cursor: nil)
        nextRequest = request
        return request
    }

    /// Returns false for an obsolete, repeated, or malformed page. Validation is
    /// atomic so a bad page never partially replaces the visible catalog.
    @discardableResult
    mutating func accept(_ page: TaskListPage, for request: Request, now: Date = Date()) -> Bool {
        guard phase == .loading, nextRequest == request,
              page.data.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(page.data.map(\.id)).count == page.data.count else { return false }
        if let cursor = page.nextCursor {
            guard !cursor.isEmpty, cursor != request.cursor, !consumedCursors.contains(cursor) else { return false }
        }
        if let cursor = request.cursor { consumedCursors.insert(cursor) }
        for task in page.data {
            // A status notification received during pagination is more recent
            // than the snapshot being assembled. Preserve it even for later pages.
            let update = eventUpdates[task.id]
            let entry = Entry(task: DiscoveredTask(id: task.id, name: task.name,
                status: update?.0 ?? task.status), observedAt: update?.1 ?? now)
            if let index = entries.firstIndex(where: { $0.id == task.id }) {
                entries[index] = entry
            } else { entries.append(entry) }
        }
        nextRequest = page.nextCursor.map { Request(generation: generation, cursor: $0) }
        if nextRequest == nil { phase = .complete }
        return true
    }

    /// The connection owner retains the token returned by refresh for events too.
    /// Unknown IDs never create phantom tasks; later pages may resolve their names.
    mutating func apply(_ change: TaskStatusChange, session: Request, now: Date = Date()) {
        guard phase != .disconnected, session.generation == generation,
              !change.threadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if phase == .loading { eventUpdates[change.threadId] = (change.status, now) }
        guard let index = entries.firstIndex(where: { $0.id == change.threadId }) else { return }
        let old = entries[index].task
        entries[index] = Entry(task: DiscoveredTask(id: old.id, name: old.name, status: change.status), observedAt: now)
    }

    mutating func disconnect() {
        generation = UUID()
        phase = .disconnected
        nextRequest = nil
        eventUpdates = [:]
    }

    func statusLabel(for id: String, now: Date = Date()) -> String {
        guard phase != .disconnected else { return "Disconnected" }
        guard let entry = entries.first(where: { $0.id == id }) else { return "Unknown task" }
        let age = now.timeIntervalSince(entry.observedAt)
        guard age >= 0, age < 5 else { return "Status out of date" }
        return entry.task.status.label
    }
}
