import XCTest
@testable import RelayCore

final class RelayCoreTests: XCTestCase {
    private func channels() throws -> (SecureChannel, SecureChannel) {
        let phone = SecureChannel(), mac = SecureChannel()
        try phone.acceptCommitment(mac.commitment)
        try mac.acceptCommitment(phone.commitment)
        try phone.acceptReveal(mac.reveal)
        try mac.acceptReveal(phone.reveal)
        return (phone, mac)
    }
    private func pair(_ a: SecureChannel, _ b: SecureChannel) throws {
        a.confirmLocal(); b.confirmLocal()
        _ = try b.open(a.seal(.init(kind: .confirmed)))
        _ = try a.open(b.seal(.init(kind: .confirmed)))
    }

    func testPairingRequiresConfirmationOnBothDevices() throws {
        let (phone, mac) = try channels()
        XCTAssertEqual(phone.verificationCode, mac.verificationCode)
        XCTAssertThrowsError(try phone.seal(.init(kind: .stateRequest)))
        phone.confirmLocal()
        _ = try mac.open(phone.seal(.init(kind: .confirmed)))
        XCTAssertFalse(phone.ready)
        XCTAssertFalse(mac.ready)
        XCTAssertThrowsError(try mac.seal(.init(kind: .stateRequest)))
        mac.confirmLocal()
        _ = try phone.open(mac.seal(.init(kind: .confirmed)))
        XCTAssertTrue(phone.ready)
        XCTAssertTrue(mac.ready)
    }

    func testEncryptedRoundTripAndReplayRejection() throws {
        let (phone, mac) = try channels()
        try pair(phone, mac)
        let packet = try phone.seal(.init(kind: .stateRequest))
        XCTAssertFalse(String(decoding: packet, as: UTF8.self).contains("stateRequest"))
        XCTAssertEqual(try mac.open(packet).kind, .stateRequest)
        XCTAssertThrowsError(try mac.open(packet))
    }

    func testTamperingAndOtherSessionsAreRejected() throws {
        let (phone, mac) = try channels()
        try pair(phone, mac)
        var packet = try phone.seal(.init(kind: .stateRequest))
        packet[packet.count - 1] ^= 1
        XCTAssertThrowsError(try mac.open(packet))
        let (otherPhone, otherMac) = try channels()
        try pair(otherPhone, otherMac)
        XCTAssertThrowsError(try otherMac.open(phone.seal(.init(kind: .stateRequest))))
    }

    func testHandshakeCannotBeReplacedOrReflected() throws {
        let a = SecureChannel(), b = SecureChannel()
        XCTAssertThrowsError(try a.acceptCommitment(a.commitment))
        XCTAssertThrowsError(try a.acceptCommitment(Data([1, 2])))
        XCTAssertThrowsError(try a.acceptReveal(b.reveal))
        try a.acceptCommitment(b.commitment)
        XCTAssertThrowsError(try a.acceptCommitment(SecureChannel().commitment))
        XCTAssertThrowsError(try a.acceptReveal(SecureChannel().reveal))
        try a.acceptReveal(b.reveal)
        XCTAssertThrowsError(try a.acceptReveal(b.reveal))
        XCTAssertThrowsError(try a.open(Data(repeating: 0, count: 66_001)))
    }

    func testEncryptedMessagesCannotBeReflectedToTheirSender() throws {
        let (phone, mac) = try channels()
        try pair(phone, mac)
        XCTAssertThrowsError(try phone.open(phone.seal(.init(kind: .stateRequest))))
    }

    func testMissingOrAmbiguousLabelsNeverMatch() {
        let button = AccessibleControl(label: "Fast mode", enabled: true, pressable: true, toggleValue: false)
        XCTAssertEqual(ControlMatcher.uniqueIndex(label: "Fast mode", controls: [button]), 0)
        XCTAssertNil(ControlMatcher.uniqueIndex(label: "Fast mode", controls: [button, button]))
        XCTAssertNil(ControlMatcher.uniqueIndex(label: "Fast", controls: [button]))
        XCTAssertNil(ControlMatcher.uniqueIndex(label: "", controls: [button]))
        var disabled = button; disabled.enabled = false
        XCTAssertNil(ControlMatcher.uniqueIndex(label: "Fast mode", controls: [disabled]))
    }

    func testCommandsRejectStaleViewsRetriesAndApprovalWithoutContext() throws {
        var gate = CommandGate()
        let state = DesktopState.demo
        let command = RelayCommand(action: .fastMode, revision: state.revision, desiredValue: true)
        try gate.validate(command, state: state)
        XCTAssertThrowsError(try gate.validate(command, state: state))
        XCTAssertThrowsError(try gate.validate(.init(action: .fastMode, revision: UUID(), desiredValue: true), state: state))
        XCTAssertThrowsError(try gate.validate(.init(action: .fastMode, revision: state.revision), state: state))
        XCTAssertThrowsError(try gate.validate(.init(action: .approve, revision: state.revision), state: state))
        XCTAssertThrowsError(try gate.validate(.init(action: .decline, revision: state.revision), state: state))
        XCTAssertThrowsError(try gate.validate(.init(action: .newChat, revision: state.revision, issuedAt: Date().addingTimeInterval(-20)), state: state))
    }

    func testDisconnectedStateHasNoEnabledControls() {
        for action in RelayAction.allCases { XCTAssertFalse(DesktopState().control(action).enabled) }
    }

    func testProtocolRoundTripPreservesCommandTargetAndDesiredState() throws {
        let command = RelayCommand(action: .fastMode, revision: UUID(), desiredValue: true)
        let decoded = try JSONDecoder().decode(RelayMessage.self, from: JSONEncoder().encode(RelayMessage(kind: .command, command: command)))
        XCTAssertEqual(decoded.command?.id, command.id)
        XCTAssertEqual(decoded.command?.revision, command.revision)
        XCTAssertEqual(decoded.command?.desiredValue, true)
    }
}
