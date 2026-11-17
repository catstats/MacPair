// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct PeerIdentity: Codable, Equatable {
    let id: String
    let name: String
    func validate() throws {
        guard UUID(uuidString: id)?.uuidString == id, !name.isEmpty, name.utf8.count <= 256 else {
            throw PairError.message("Invalid device identity")
        }
    }
    // A fresh public identity for each app process prevents a still-open peer
    // from selecting a credential whose counterpart exited and lost its memory.
    private static let processIdentity = PeerIdentity(id: UUID().uuidString,
        name: String((Host.current().localizedName ?? "Mac").prefix(60)))
    static func local() -> PeerIdentity { processIdentity }
}

struct TrustedDevice: Codable, Identifiable {
    let id: String // Shared, non-secret pairing identifier; never the PIN.
    let peer: PeerIdentity
    let secret: Data // 256 random-looking bits derived from the authenticated exchange.
    let createdAt: Date
    func validate() throws {
        try peer.validate()
        guard id.utf8.count == 32, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              secret.count == 32 else { throw PairError.message("Invalid saved pairing") }
    }
    var summary: TrustedDeviceSummary { TrustedDeviceSummary(id: id, peer: peer) }
}
struct TrustedDeviceSummary: Identifiable {
    let id: String
    let peer: PeerIdentity
}

/// Session-only pairing credentials. No Keychain, preferences or file access.
/// A new app process starts with an empty store and a new public identity.
final class TrustStore {
    private let lock = NSLock()
    private var memory: [String: TrustedDevice] = [:]

    func all() throws -> [TrustedDevice] {
        lock.withLock { Array(memory.values) }
    }
    func credential(id: String) throws -> TrustedDevice? {
        lock.withLock { memory[id] }
    }
    func credential(forPeer id: String) throws -> TrustedDevice? {
        try all().filter { $0.peer.id == id }.max { $0.createdAt < $1.createdAt }
    }
    func save(_ record: TrustedDevice) throws {
        try record.validate()
        lock.withLock { memory[record.id] = record }
    }
    func forget(id: String) throws {
        _ = lock.withLock { memory.removeValue(forKey: id) }
    }
    func forgetPeer(_ peerID: String, keeping id: String? = nil) throws {
        lock.withLock {
            memory = memory.filter { $0.value.peer.id != peerID || $0.key == id }
        }
    }
}

struct PairingOffer: Codable {
    let version: Int
    let identity: PeerIdentity
    let targetID: String
    let credentialID: String?
    let message: Data
    func validate() throws {
        try identity.validate()
        guard version == Wire.version, UUID(uuidString: targetID)?.uuidString == targetID, message.count == 32,
              credentialID == nil || (credentialID!.utf8.count == 32 && credentialID!.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })) else {
            throw PairError.message("Invalid secure pairing message")
        }
    }
}
