// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security

struct PeerIdentity: Codable, Equatable {
    let id: String
    let name: String
    func validate() throws {
        guard UUID(uuidString: id)?.uuidString == id, !name.isEmpty, name.utf8.count <= 256 else {
            throw PairError.message("Invalid device identity")
        }
    }
    static func local() -> PeerIdentity {
        let key = "MacPairLocalDeviceID"
        let id = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return PeerIdentity(id: id, name: String((Host.current().localizedName ?? "Mac").prefix(60)))
    }
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

/// Stores only strong per-device credentials. Synchronization is disabled;
/// the six-digit code is never written to Keychain or UserDefaults.
/// Memory-only instances keep diagnostics/previews out of the user's Keychain.
final class TrustStore {
    private let service: String
    private let memoryOnly: Bool
    private let lock = NSLock()
    private var memory: [String: TrustedDevice] = [:]
    init(memoryOnly: Bool = false, service: String = "local.macpair.prototype.trusted-devices.v1") {
        self.memoryOnly = memoryOnly; self.service = service
    }
    private func query(_ id: String? = nil) -> [String: Any] {
        // The local login keychain works with this ad-hoc signed prototype.
        // Data-protection access groups require Apple provisioning (TN3137).
        // Omitting synchronizable keeps these items local; iOS-only accessible
        // attributes must not be supplied to the file-based implementation.
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service]
        if let id { result[kSecAttrAccount as String] = id }
        return result
    }
    private func check(_ status: OSStatus, _ operation: LocalizedMessage) throws {
        guard status == errSecSuccess else {
            throw PairError.message("macOS Keychain \(operation) failed (\(status))")
        }
    }
    func all() throws -> [TrustedDevice] {
        if memoryOnly { return lock.withLock { Array(memory.values) } }
        // File-based macOS keychains do not support returning all password
        // data at once. List our item attributes, then fetch each owned item.
        var q = query(); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status, "list pairings")
        var records: [TrustedDevice] = []
        for attributes in result as? [[String: Any]] ?? [] {
            if let id = attributes[kSecAttrAccount as String] as? String,
               let record = try credential(id: id) { records.append(record) }
        }
        return records
    }
    func credential(id: String) throws -> TrustedDevice? {
        if memoryOnly { return lock.withLock { memory[id] } }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status, "read pairing")
        guard let data = result as? Data else { throw PairError.message("Invalid saved pairing") }
        let record = try JSONDecoder().decode(TrustedDevice.self, from: data)
        try record.validate(); return record
    }
    func credential(forPeer id: String) throws -> TrustedDevice? {
        try all().filter { $0.peer.id == id }.max { $0.createdAt < $1.createdAt }
    }
    func save(_ record: TrustedDevice) throws {
        try record.validate()
        if memoryOnly { lock.withLock { memory[record.id] = record }; return }
        let value = try JSONEncoder().encode(record)
        let update = SecItemUpdate(query(record.id) as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if update == errSecItemNotFound {
            var q = query(record.id)
            q[kSecValueData as String] = value
            q[kSecAttrLabel as String] = "MacPair · " + record.peer.name
            try check(SecItemAdd(q as CFDictionary, nil), "save pairing")
        } else { try check(update, "update pairing") }
    }
    func forget(id: String) throws {
        if memoryOnly { _ = lock.withLock { memory.removeValue(forKey: id) }; return }
        let status = SecItemDelete(query(id) as CFDictionary)
        if status != errSecItemNotFound { try check(status, "forget pairing") }
    }
    func forgetPeer(_ peerID: String, keeping id: String? = nil) throws {
        for record in try all() where record.peer.id == peerID && record.id != id { try forget(id: record.id) }
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
