import Foundation
import CryptoKit

/// Ephemeral keys: pairing is required again after either device disconnects.
/// The user compares the ECDH-derived code on both screens before any control data flows.
final class SecureChannel {
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    private var remoteCommitment: Data?
    private var remotePublicKey: Data?
    private var key: SymmetricKey?
    private var sent: UInt64 = 0
    private var received: UInt64 = 0
    private(set) var verificationCode: String?
    private(set) var localConfirmed = false
    private(set) var remoteConfirmed = false
    var publicKey: Data { privateKey.publicKey.rawRepresentation }
    var reveal: Data { publicKey + nonce }
    var commitment: Data { Data(SHA256.hash(data: reveal)) }
    var ready: Bool { key != nil && localConfirmed && remoteConfirmed }

    func acceptCommitment(_ data: Data) throws {
        guard remoteCommitment == nil, data.count == 32, data != commitment else { throw RelayFailure.invalidHandshake }
        remoteCommitment = data
    }

    func acceptReveal(_ data: Data) throws {
        guard data.count == 64, let remoteCommitment,
              Data(SHA256.hash(data: data)) == remoteCommitment else { throw RelayFailure.invalidHandshake }
        let remote = Data(data.prefix(32))
        guard key == nil, remote.count == 32, remote != publicKey else { throw RelayFailure.invalidHandshake }
        remotePublicKey = remote
        let remoteKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remote)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: remoteKey)
        let transcript = publicKey.lexicographicallyPrecedes(remote) ? publicKey + remote : remote + publicKey
        key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript,
                                            sharedInfo: Data("PalmRelay-v1".utf8), outputByteCount: 32)
        let digest = SHA256.hash(data: transcript)
        let number = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 100_000_000
        let digits = String(format: "%08u", number)
        verificationCode = "\(digits.prefix(4)) \(digits.suffix(4))"
    }

    func confirmLocal() { if key != nil { localConfirmed = true } }

    private struct Payload: Codable { let sender: Data; let sequence: UInt64; let message: RelayMessage }

    func seal(_ message: RelayMessage) throws -> Data {
        guard let key, ready || (message.kind == .confirmed && localConfirmed) else { throw RelayFailure.unpaired }
        sent += 1
        let data = try JSONEncoder().encode(Payload(sender: publicKey, sequence: sent, message: message))
        guard data.count <= 65_536 else { throw RelayFailure.oversized }
        return try AES.GCM.seal(data, using: key).combined!
    }

    func open(_ data: Data) throws -> RelayMessage {
        guard data.count <= 66_000 else { throw RelayFailure.oversized }
        guard let key else { throw RelayFailure.unpaired }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        let payload = try JSONDecoder().decode(Payload.self, from: clear)
        guard payload.sender == remotePublicKey else { throw RelayFailure.invalidHandshake }
        guard payload.sequence == received + 1 else { throw RelayFailure.replay }
        guard ready || payload.message.kind == .confirmed else { throw RelayFailure.unpaired }
        received = payload.sequence
        if payload.message.kind == .confirmed { remoteConfirmed = true }
        return payload.message
    }
}
