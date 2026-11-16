// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// Human-readable code policy. Leading zeroes are part of the secret.
enum PairingCode {
    static func normalize(_ input: String) -> String { input.filter { !$0.isWhitespace && $0 != "-" } }
    static func isValid(_ input: String) -> Bool {
        let code = normalize(input)
        return code.utf8.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) }
    }
    static func generate(excluding previous: String? = nil) -> String {
        var code: String
        repeat { code = String(format: "%06d", Int.random(in: 0..<1_000_000)) } while code == previous
        return code
    }
}

/// Monotonic elapsed time includes sleep, so an invitation cannot outlive
/// its five-minute window by sleeping the Mac or changing its wall clock.
enum PairingTime {
    private static let clock = ContinuousClock()
    private static let started = clock.now
    static var now: TimeInterval {
        let parts = started.duration(to: clock.now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// Continuous elapsed time controls expiry and the global attempt
/// budget. No per-IP allowance that an attacker can evade by changing address.
struct PairingGate {
    static let lifetime: TimeInterval = 300
    static let cooldown: TimeInterval = 30
    static let maximumFailures = 5
    private(set) var expiresAt: TimeInterval?
    private(set) var lockedUntil: TimeInterval?
    private(set) var failures = 0
    func isLocked(at now: TimeInterval) -> Bool { (lockedUntil ?? 0) > now }
    func accepts(at now: TimeInterval) -> Bool { !isLocked(at: now) && (expiresAt ?? 0) > now }
    mutating func issue(at now: TimeInterval) -> Bool {
        guard !isLocked(at: now) else { return false }
        if lockedUntil != nil { failures = 0; lockedUntil = nil }
        expiresAt = now + Self.lifetime
        return true
    }
    mutating func invalidate() { expiresAt = nil }
    mutating func consume() { expiresAt = nil; failures = 0 }
    @discardableResult mutating func failed(at now: TimeInterval) -> Bool {
        failures += 1
        guard failures >= Self.maximumFailures else { return false }
        expiresAt = nil
        lockedUntil = now + Self.cooldown
        return true
    }
}

/// Establishes a random session key from a short code without transmitting the
/// code or exposing an offline password verifier. The native primitive is the
/// existing BoringSSL SPAKE2 implementation vendored by Apple Swift Crypto.
final class PasswordExchange {
    private let native: MPPasswordExchange
    private let host: Bool
    let message: Data
    convenience init(host: Bool, code: String) throws {
        guard PairingCode.isValid(code) else { throw PairError.message("Cannot prepare secure pairing") }
        try self.init(host: host, secret: Data(PairingCode.normalize(code).utf8), hostID: "host", displayID: "display")
    }
    init(host: Bool, secret: Data, hostID: String, displayID: String) throws {
        guard (6...64).contains(secret.count), let native = MPPasswordExchange(host: host, secret: secret, hostID: hostID, displayID: displayID) else {
            throw PairError.message("Cannot prepare secure pairing")
        }
        self.native = native
        self.host = host
        self.message = native.message
    }
    func finish(peerMessage: Data) throws -> PairingKeys {
        guard peerMessage.count == 32, let material = native.sharedKey(forMessage: peerMessage), material.count == 64 else {
            throw PairError.message("Invalid secure pairing message")
        }
        let context = Data("MacPair/v3/SPAKE2/key-schedule".utf8)
        let root = SymmetricKey(data: material)
        func derive(_ label: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: root, salt: context,
                info: Data(label.utf8), outputByteCount: 32)
        }
        let toDisplay = derive("host-to-display/AES-256-GCM")
        let toHost = derive("display-to-host/AES-256-GCM")
        let proofKey = derive("mutual-key-confirmation/HMAC-SHA256")
        return PairingKeys(send: host ? toDisplay : toHost, receive: host ? toHost : toDisplay,
            confirmation: proofKey, host: host,
            resumeSecret: derive("remembered-device/secret").withUnsafeBytes { Data($0) },
            resumeID: derive("remembered-device/identifier").withUnsafeBytes { Data($0.prefix(16)).map { String(format: "%02x", $0) }.joined() })
    }
}

struct PairingKeys {
    let send: SymmetricKey
    let receive: SymmetricKey
    private let confirmation: SymmetricKey
    private let host: Bool
    let resumeSecret: Data
    let resumeID: String
    init(send: SymmetricKey, receive: SymmetricKey, confirmation: SymmetricKey, host: Bool, resumeSecret: Data, resumeID: String) {
        self.send = send; self.receive = receive; self.confirmation = confirmation; self.host = host
        self.resumeSecret = resumeSecret; self.resumeID = resumeID
    }
    private func proof(forHost: Bool) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(("MacPair/v3/confirm/" + (forHost ? "host" : "display")).utf8), using: confirmation))
    }
    var localProof: Data { proof(forHost: host) }
    func verifyPeer(_ proof: Data) -> Bool {
        guard proof.count == 32 else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(proof,
            authenticating: Data(("MacPair/v3/confirm/" + (host ? "display" : "host")).utf8), using: confirmation)
    }
}

/// All post-pairing packets, including hello, heartbeat and video, are sealed.
/// Separate directional keys and strictly ordered counters prevent nonce reuse,
/// reflection and replay. A failed authentication closes the whole connection.
final class PacketCipher {
    static let overhead = 37 // inner kind + sequence + GCM nonce/tag
    private let keys: PairingKeys
    private var sendSequence: UInt64 = 0
    private var receiveSequence: UInt64 = 0
    init(keys: PairingKeys) { self.keys = keys }
    private func nonceData(_ sequence: UInt64) -> Data {
        var data = Data(repeating: 0, count: 4); data.appendBE(sequence); return data
    }
    private func associatedData(_ sequence: UInt64) -> Data {
        var data = Data("MacPair/v3/record".utf8); data.appendBE(sequence); return data
    }
    func seal(_ kind: PacketKind, _ body: Data) throws -> Data {
        guard ![.pairOffer, .pairProof, .sealed].contains(kind), sendSequence < UInt64.max,
              body.count + Self.overhead + 1 <= Wire.maximumPacket else {
            throw PairError.message("Invalid encrypted packet")
        }
        var plain = Data([kind.rawValue]); plain.append(body)
        let box = try AES.GCM.seal(plain, using: keys.send,
            nonce: AES.GCM.Nonce(data: nonceData(sendSequence)),
            authenticating: associatedData(sendSequence))
        guard let combined = box.combined else { throw PairError.message("Invalid encrypted packet") }
        var packet = Data(); packet.appendBE(sendSequence); packet.append(combined)
        sendSequence += 1
        return packet
    }
    func open(_ body: Data) throws -> Packet {
        guard body.count >= Self.overhead, receiveSequence < UInt64.max,
              body.uint64BE() == receiveSequence else {
            throw PairError.message("Encrypted packet was altered or replayed")
        }
        let box = try AES.GCM.SealedBox(combined: body.dropFirst(8))
        guard Data(box.nonce) == nonceData(receiveSequence) else {
            throw PairError.message("Encrypted packet was altered or replayed")
        }
        let plain = try AES.GCM.open(box, using: keys.receive, authenticating: associatedData(receiveSequence))
        guard let first = plain.first, let kind = PacketKind(rawValue: first),
              ![.pairOffer, .pairProof, .sealed].contains(kind) else {
            throw PairError.message("Invalid encrypted packet")
        }
        receiveSequence += 1
        return Packet(kind: kind, body: Data(plain.dropFirst()))
    }
}
