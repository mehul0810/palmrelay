import Foundation
import Combine
import MultipeerConnectivity

@MainActor
final class PeerLink: NSObject, ObservableObject {
    @Published var nearby: [MCPeerID] = []
    @Published var peerName: String?
    @Published var code: String?
    @Published var paired = false
    @Published var confirmed = false
    @Published var status = "Not connected"
    @Published var running = false
    var onMessage: ((RelayMessage) -> Void)?
    var onDisconnect: (() -> Void)?
    private let host: Bool
    private let peer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var selected: MCPeerID?
    private var channel = SecureChannel()
    private var pairingDeadline: Task<Void, Never>?
    private let service = "palmrelay-v1"

    init(host: Bool) {
        self.host = host
        #if os(macOS)
        peer = MCPeerID(displayName: String((Host.current().localizedName ?? "Mac").prefix(50)))
        #else
        peer = MCPeerID(displayName: "PalmRelay iPhone")
        #endif
        super.init()
        makeSession()
    }

    private func makeSession() {
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func start() {
        guard !running else { return }
        running = true
        if host {
            advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["role": "mac"], serviceType: service)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
            status = "Ready for your iPhone"
        } else {
            browser = MCNearbyServiceBrowser(peer: peer, serviceType: service)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
            status = "Looking for your Mac…"
        }
    }

    func connect(_ remote: MCPeerID) {
        guard selected == nil else { return }
        selected = remote
        peerName = remote.displayName
        status = "Connecting…"
        browser?.invitePeer(remote, to: session, withContext: nil, timeout: 20)
        setDeadline()
    }

    private func setDeadline() {
        pairingDeadline?.cancel()
        pairingDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, !self.paired else { return }
            self.stop()
            self.status = "Pairing timed out. Start again."
        }
    }

    func confirmPairing() {
        guard code != nil, !confirmed else { return }
        channel.confirmLocal()
        confirmed = true
        do { try transmit(.init(kind: .confirmed)); updatePairing() }
        catch { fail(error) }
    }

    func send(_ message: RelayMessage) {
        guard paired else { return }
        do { try transmit(message) } catch { fail(error) }
    }

    private func transmit(_ message: RelayMessage) throws {
        guard let selected else { throw RelayFailure.unpaired }
        let sealed = try channel.seal(message)
        try session.send(Data([1]) + sealed, toPeers: [selected], with: .reliable)
    }

    private func updatePairing() {
        paired = channel.ready
        status = paired ? "Connected securely" : "Compare the code on both devices"
        if paired { pairingDeadline?.cancel(); code = nil }
    }

    func stop() {
        pairingDeadline?.cancel()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.delegate = nil
        session.disconnect()
        selected = nil
        peerName = nil
        nearby = []
        code = nil
        paired = false
        confirmed = false
        running = false
        status = "Not connected"
        channel = SecureChannel()
        makeSession()
        onDisconnect?()
    }

    private func fail(_ error: Error) {
        stop()
        status = error.localizedDescription
    }

    private func receive(_ data: Data, from remote: MCPeerID) {
        guard selected == remote, !data.isEmpty else { return }
        do {
            switch data.first {
            case 0:
                guard data.count == 33 else { throw RelayFailure.invalidHandshake }
                try channel.acceptCommitment(Data(data.dropFirst()))
                try session.send(Data([2]) + channel.reveal, toPeers: [remote], with: .reliable)
            case 2:
                guard data.count == 65 else { throw RelayFailure.invalidHandshake }
                try channel.acceptReveal(Data(data.dropFirst()))
                code = channel.verificationCode
                updatePairing()
            case 1:
                let message = try channel.open(Data(data.dropFirst()))
                updatePairing()
                if paired && message.kind != .confirmed { onMessage?(message) }
            default: throw RelayFailure.invalidHandshake
            }
        } catch { fail(error) }
    }
}

extension PeerLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard session === self.session, peerID == self.selected else { return }
            if state == .connected {
                do { try session.send(Data([0]) + self.channel.commitment, toPeers: [peerID], with: .reliable) }
                catch { self.fail(error) }
            } else if state == .notConnected {
                self.stop()
                self.status = "Connection ended. Pair again to resume."
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard session === self.session else { return }
            self.receive(data, from: peerID)
        }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerLink: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            guard advertiser === self.advertiser, self.running, self.host, self.selected == nil else { invitationHandler(false, nil); return }
            self.selected = peerID
            self.peerName = peerID.displayName
            self.status = "Waiting to verify your phone"
            self.setDeadline()
            invitationHandler(true, self.session)
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.fail(error) }
    }
}

extension PeerLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard browser === self.browser, self.running else { return }
            if info?["role"] == "mac", !self.nearby.contains(peerID) { self.nearby.append(peerID) }
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.nearby.removeAll { $0 == peerID } }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.fail(error) }
    }
}
