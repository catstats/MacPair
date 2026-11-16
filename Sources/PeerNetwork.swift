// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network

enum PeerNetwork {
    // Separate discovery prevents an old TLS/12-character build being offered
    // as a compatible six-digit peer.
    static let serviceType = "_macpair-v3._tcp"
    static func normalize(_ code: String) -> String { PairingCode.normalize(code) }
    static func newCode() -> String { PairingCode.generate() }
    static func parameters(interface: NWInterface? = nil) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 12
        // SPAKE2 authenticates the peers before PacketCipher permits any app
        // packets. A six-digit value is never used directly as a TLS PSK.
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        if let interface { parameters.requiredInterface = interface }
        return parameters
    }
    static func discoveryParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        return parameters
    }
}

struct DiscoveredPeer: Identifiable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    let directInterface: NWInterface?
    let interfaces: String
    let deviceIdentity: PeerIdentity?
    var isDirect: Bool { directInterface != nil }

    init?(_ result: NWBrowser.Result) {
        guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
        self.id = "\(name).\(type).\(domain)"
        self.name = name
        if case .bonjour(let record) = result.metadata, let value = record["id"], let id = UUID(uuidString: value)?.uuidString {
            self.deviceIdentity = PeerIdentity(id: id, name: String(name.prefix(60)))
        } else { self.deviceIdentity = nil }
        self.directInterface = result.interfaces.first { $0.name.hasPrefix("awdl") }
        self.interfaces = result.interfaces.map(\.name).sorted().joined(separator: ", ")
        // Keep the Bonjour service endpoint and its interface scope. Do not resolve
        // to an IPv4 address: AWDL uses interface-scoped IPv6.
        self.endpoint = .service(name: name, type: type, domain: domain, interface: directInterface)
    }
}

/// All connection state and parsing live on one queue. Callback delivery is
/// configurable so the command-line tests don't depend on a GUI run loop.
final class PeerLink {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "MacPair.wire")
    private let callbackQueue: DispatchQueue
    private var parser = PacketParser()
    private var timer: DispatchSourceTimer?
    private var deadline: DispatchWorkItem?
    private var lastReceived = DispatchTime.now().uptimeNanoseconds
    private var isClosed = false
    private(set) var isReady = false
    private let host: Bool
    private let code: String?
    private let identity: PeerIdentity
    private let expectedPeer: PeerIdentity?
    private let trusted: TrustedDevice?
    private let lookupTrusted: (String) throws -> TrustedDevice?
    private var peerIdentity: PeerIdentity?
    private var candidateCredential: TrustedDevice?
    private(set) var authenticatedCredential: TrustedDevice?
    private(set) var isResuming = false
    private var exchange: PasswordExchange?
    private var pendingKeys: PairingKeys?
    private var cipher: PacketCipher?
    private var preAuthenticationBytes = 0
    var onReady: (() -> Void)?
    var onPacket: ((Packet) -> Void)?
    var onClosed: ((LocalizedMessage) -> Void)?
    var onPath: ((LocalizedMessage) -> Void)?
    var onRTT: ((Double) -> Void)?

    init(_ connection: NWConnection, host: Bool, code: String?, identity: PeerIdentity,
         expectedPeer: PeerIdentity? = nil, trusted: TrustedDevice? = nil,
         lookupTrusted: @escaping (String) throws -> TrustedDevice? = { _ in nil },
         callbackQueue: DispatchQueue = .main) {
        self.connection = connection
        self.host = host
        self.code = code
        self.identity = identity
        self.expectedPeer = expectedPeer
        self.trusted = trusted
        self.lookupTrusted = lookupTrusted
        self.isResuming = trusted != nil
        self.callbackQueue = callbackQueue
    }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if CommandLine.arguments.contains("--trace") { print("TRACE NWConnection: \(state)") }
            switch state {
            case .ready:
                do {
                    try self.identity.validate()
                    if self.host {
                        guard let peer = self.expectedPeer else { throw PairError.message("Invalid device identity") }
                        try peer.validate()
                        let secret: Data
                        if let trusted = self.trusted {
                            try trusted.validate()
                            guard trusted.peer.id == peer.id else { throw PairError.message("Invalid saved pairing") }
                            secret = trusted.secret
                            self.candidateCredential = trusted
                        } else {
                            guard let code = self.code, PairingCode.isValid(code) else { throw PairError.message("Cannot prepare secure pairing") }
                            secret = Data(PairingCode.normalize(code).utf8)
                        }
                        let exchange = try PasswordExchange(host: true, secret: secret, hostID: self.identity.id, displayID: peer.id)
                        self.exchange = exchange
                        let offer = PairingOffer(version: Wire.version, identity: self.identity, targetID: peer.id,
                            credentialID: self.trusted?.id, message: exchange.message)
                        self.sendRaw(.pairOffer, try JSONEncoder().encode(offer))
                    }
                    self.reportPath(self.connection.currentPath)
                    self.receive()
                } catch { self.finish(error.appMessage) }
            case .waiting(let error):
                self.deliver { $0.onPath?("Waiting for network: \(error.localizedDescription)") }
            case .failed(let error):
                self.finish("Connection failed (check the code, Wi-Fi, and Local Network permission): \(error.localizedDescription)")
            case .cancelled: self.finish("Connection closed")
            default: break
            }
        }
        connection.pathUpdateHandler = { [weak self] path in self?.reportPath(path) }
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !self.isReady else { return }
            self.finish("Connection timed out. Check the pairing code, Wi-Fi, and Local Network permission.")
        }
        self.deadline = deadline
        queue.asyncAfter(deadline: .now() + 15, execute: deadline)
        connection.start(queue: queue)
    }
    private func reportPath(_ path: NWPath?) {
        guard let path else { return }
        let names = path.availableInterfaces.map(\.name).joined(separator: ", ")
        deliver { $0.onPath?("Network path: \(names.isEmpty ? "waiting for interface" : names)") }
    }
    func send(_ kind: PacketKind, _ body: Data = Data(), completion: ((Bool) -> Void)? = nil) {
        guard body.count + PacketCipher.overhead + 1 <= Wire.maximumPacket else { completion?(false); return }
        queue.async { [weak self] in
            guard let self, !self.isClosed, self.isReady, let cipher = self.cipher else { completion?(false); return }
            do { self.sendRaw(.sealed, try cipher.seal(kind, body), completion: completion) }
            catch { completion?(false); self.finish(error.appMessage) }
        }
    }
    // Called only on the serial wire queue, including the two initial PAKE records.
    private func sendRaw(_ kind: PacketKind, _ body: Data, completion: ((Bool) -> Void)? = nil) {
        connection.send(content: Wire.frame(kind, body), completion: .contentProcessed { [weak self] error in
            completion?(error == nil)
            if let error { self?.finish("Send failed: \(error.localizedDescription)") }
        })
    }
    private func handlePairing(_ packet: Packet) throws {
        switch packet.kind {
        case .pairOffer:
            guard pendingKeys == nil, packet.body.count <= 1536 else {
                throw PairError.message("Invalid secure pairing message")
            }
            let offer = try JSONDecoder().decode(PairingOffer.self, from: packet.body)
            try offer.validate()
            guard offer.targetID == identity.id else { throw PairError.message("Invalid device identity") }
            let exchange: PasswordExchange
            if host {
                guard let current = self.exchange, offer.identity.id == expectedPeer?.id,
                      offer.credentialID == trusted?.id else { throw PairError.message("Invalid device identity") }
                exchange = current
            } else {
                guard self.exchange == nil, peerIdentity == nil else { throw PairError.message("Invalid secure pairing message") }
                let secret: Data
                if let id = offer.credentialID {
                    guard let credential = try lookupTrusted(id), credential.peer.id == offer.identity.id else {
                        throw PairError.message("Saved pairing is no longer available. Pair again with a new code.")
                    }
                    try credential.validate()
                    secret = credential.secret
                    candidateCredential = credential
                    isResuming = true
                } else {
                    guard let code, PairingCode.isValid(code) else {
                        throw PairError.message("Pairing code expired. Start waiting again for a new code.")
                    }
                    secret = Data(PairingCode.normalize(code).utf8)
                }
                exchange = try PasswordExchange(host: false, secret: secret, hostID: offer.identity.id, displayID: identity.id)
                let response = PairingOffer(version: Wire.version, identity: identity, targetID: offer.identity.id,
                    credentialID: offer.credentialID, message: exchange.message)
                sendRaw(.pairOffer, try JSONEncoder().encode(response))
            }
            peerIdentity = offer.identity
            let keys = try exchange.finish(peerMessage: offer.message)
            self.exchange = nil
            pendingKeys = keys
            if candidateCredential == nil {
                candidateCredential = TrustedDevice(id: keys.resumeID, peer: offer.identity,
                    secret: keys.resumeSecret, createdAt: Date())
            }
            sendRaw(.pairProof, keys.localProof)
        case .pairProof:
            guard let keys = pendingKeys, keys.verifyPeer(packet.body) else {
                throw PairError.message("Pairing failed. Check the six-digit code currently shown on the display Mac.")
            }
            guard let candidateCredential else { throw PairError.message("Invalid saved pairing") }
            authenticatedCredential = candidateCredential
            cipher = PacketCipher(keys: keys)
            pendingKeys = nil
            isReady = true
            deadline?.cancel()
            lastReceived = DispatchTime.now().uptimeNanoseconds
            deliver { $0.onReady?() }
            startHeartbeat()
        default:
            throw PairError.message("Update MacPair on both Macs to use six-digit pairing")
        }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: isReady ? 256 * 1024 : 1024) { [weak self] data, _, complete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                if !self.isReady {
                    self.preAuthenticationBytes += data.count
                    guard self.preAuthenticationBytes <= 4096 else {
                        self.finish("Invalid secure pairing message"); return
                    }
                }
                self.lastReceived = DispatchTime.now().uptimeNanoseconds
                do {
                    for incoming in try self.parser.append(data) {
                        if !self.isReady { try self.handlePairing(incoming); continue }
                        guard incoming.kind == .sealed, let cipher = self.cipher else {
                            throw PairError.message("Unencrypted packet rejected")
                        }
                        let packet = try cipher.open(incoming.body)
                        if packet.kind == .ping {
                            guard packet.body.count == 8 else { throw PairError.message("Invalid heartbeat packet") }
                            self.send(.pong, packet.body)
                        } else if packet.kind == .pong {
                            guard packet.body.count == 8 else { throw PairError.message("Invalid heartbeat reply") }
                            let now = DispatchTime.now().uptimeNanoseconds
                            let stamp = packet.body.uint64BE()
                            if stamp <= now {
                                let ms = Double(now - stamp) / 1_000_000
                                self.deliver { $0.onRTT?(ms) }
                            }
                        } else {
                            self.deliver { $0.onPacket?(packet) }
                        }
                    }
                } catch { self.finish(error.appMessage); return }
            }
            if let error { self.finish("Receive failed: \(error.localizedDescription)") }
            else if complete { self.finish("The other Mac disconnected") }
            else { self.receive() }
        }
    }
    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            if now - self.lastReceived > 12_000_000_000 {
                self.finish("The other Mac stopped responding. Connection closed.")
                return
            }
            var body = Data()
            body.appendBE(now)
            self.send(.ping, body)
        }
        self.timer = timer
        timer.resume()
    }
    private func deliver(_ body: @escaping (PeerLink) -> Void) {
        callbackQueue.async { [weak self] in if let self { body(self) } }
    }
    private func finish(_ reason: LocalizedMessage) {
        guard !isClosed else { return }
        isClosed = true
        isReady = false
        exchange = nil
        pendingKeys = nil
        cipher = nil
        deadline?.cancel()
        timer?.cancel()
        timer = nil
        connection.stateUpdateHandler = nil
        connection.pathUpdateHandler = nil
        connection.cancel()
        deliver { $0.onClosed?(reason) }
    }
    func cancel() { queue.async { [weak self] in self?.finish("Connection ended") } }
    deinit { deadline?.cancel(); timer?.cancel(); connection.cancel() }
}
