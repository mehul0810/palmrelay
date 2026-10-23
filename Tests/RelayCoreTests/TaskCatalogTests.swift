import XCTest
@testable import RelayCore

final class TaskCatalogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private func page(_ json: String) throws -> TaskListPage {
        try JSONDecoder().decode(TaskListPage.self, from: Data(json.utf8))
    }
    private func task(_ id: String, _ status: String = "idle") -> DiscoveredTask {
        DiscoveredTask(id: id, name: "Same name", status: .init(type: status, activeFlags: nil))
    }

    func testDocumentedSummaryResponseAndUnknownStatus() throws {
        let result = try page(#"{"data":[{"id":"a","name":"Title","preview":"ignored private preview","status":{"type":"notLoaded"}},{"id":"b","status":{"type":"futureStatus"}}],"nextCursor":null}"#)
        var catalog = TaskCatalog()
        let request = catalog.refresh()
        XCTAssertTrue(catalog.accept(result, for: request, now: now))
        XCTAssertEqual(catalog.phase, .complete)
        XCTAssertEqual(catalog.entries[0].task.displayName, "Title")
        XCTAssertEqual(catalog.entries[1].task.displayName, "Untitled task")
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now), "Not loaded")
        XCTAssertEqual(catalog.statusLabel(for: "b", now: now), "Unknown status")
    }

    func testPaginationUsesIDsAndRejectsRepeatedPages() {
        var catalog = TaskCatalog()
        let first = catalog.refresh()
        XCTAssertTrue(catalog.accept(.init(data: [task("a")], nextCursor: "next"), for: first, now: now))
        let second = catalog.nextRequest!
        XCTAssertFalse(catalog.accept(.init(data: [task("x")], nextCursor: nil), for: first, now: now))
        XCTAssertTrue(catalog.accept(.init(data: [task("a", "active"), task("b")], nextCursor: nil), for: second, now: now))
        XCTAssertEqual(catalog.entries.map(\.id), ["a", "b"])
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now), "Active")
    }

    func testRefreshAndDisconnectInvalidateRequestsAndEvents() {
        var catalog = TaskCatalog()
        let old = catalog.refresh()
        let current = catalog.refresh()
        XCTAssertFalse(catalog.accept(.init(data: [task("old")], nextCursor: nil), for: old))
        XCTAssertTrue(catalog.accept(.init(data: [task("a")], nextCursor: nil), for: current, now: now))
        catalog.apply(.init(threadId: "a", status: .init(type: "active", activeFlags: nil)), session: old, now: now)
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now), "Idle")
        catalog.disconnect()
        catalog.apply(.init(threadId: "a", status: .init(type: "active", activeFlags: nil)), session: current, now: now)
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now), "Disconnected")
        XCTAssertFalse(catalog.accept(.init(data: [], nextCursor: nil), for: current))
        XCTAssertNil(catalog.nextRequest)
    }

    func testEventsDuringPaginationWinOverSnapshot() throws {
        var catalog = TaskCatalog()
        let session = catalog.refresh()
        let event = try JSONDecoder().decode(TaskStatusChange.self, from: Data(#"{"threadId":"a","status":{"type":"active","activeFlags":["waitingOnApproval"]}}"#.utf8))
        catalog.apply(event, session: session, now: now)
        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertTrue(catalog.accept(.init(data: [task("a")], nextCursor: nil), for: session, now: now.addingTimeInterval(1)))
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now), "Waiting for approval")
        // A status flag is informational; it never grants approval capability.
        XCTAssertTrue(RelayAction.approve.requiresStructuredIntegration)
    }

    func testFreshnessBoundariesAndFutureClock() {
        var catalog = TaskCatalog()
        let request = catalog.refresh()
        catalog.accept(.init(data: [task("a")], nextCursor: nil), for: request, now: now)
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now.addingTimeInterval(4.99)), "Idle")
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now.addingTimeInterval(5)), "Status out of date")
        XCTAssertEqual(catalog.statusLabel(for: "a", now: now.addingTimeInterval(-1)), "Status out of date")
    }

    func testMalformedPageAndCursorCycleLeaveStateUnchanged() {
        var catalog = TaskCatalog()
        let first = catalog.refresh()
        XCTAssertFalse(catalog.accept(.init(data: [task("a"), task("a")], nextCursor: nil), for: first))
        XCTAssertFalse(catalog.accept(.init(data: [task(" ")], nextCursor: nil), for: first))
        XCTAssertTrue(catalog.entries.isEmpty)
        catalog.accept(.init(data: [task("a")], nextCursor: "one"), for: first)
        let second = catalog.nextRequest!
        XCTAssertFalse(catalog.accept(.init(data: [task("b")], nextCursor: "one"), for: second))
        catalog.accept(.init(data: [], nextCursor: "two"), for: second)
        XCTAssertFalse(catalog.accept(.init(data: [task("b")], nextCursor: "one"), for: catalog.nextRequest!))
        XCTAssertEqual(catalog.entries.map(\.id), ["a"])
    }

    func testEmptyResultCompletesAndRequiredStatusCannotBeFabricated() throws {
        var catalog = TaskCatalog()
        let request = catalog.refresh()
        XCTAssertTrue(catalog.accept(try page(#"{"data":[],"nextCursor":null}"#), for: request))
        XCTAssertEqual(catalog.phase, .complete)
        XCTAssertThrowsError(try page(#"{"data":[{"id":"a"}],"nextCursor":null}"#))
    }
}
