// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import Security
import CryptoKit

enum PeerNetwork {
    static let serviceType = "_macpair._tcp"
    static func normalize(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }
    static func newCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var random = SystemRandomNumberGenerator()
        let chars = (0..<12).map { _ in alphabet.randomElement(using: &random)! }
        return stride(from: 0, to: chars.count, by: 4)
            .map { String(chars[$0..<($0 + 4)]) }.joined(separator: "-")
    }
    private static func dispatchData(_ bytes: Data) -> dispatch_data_t {
        bytes.withUnsafeBytes { DispatchData(bytes: $0) } as dispatch_data_t
    }
    static func parameters(code: String, interface: NWInterface? = nil) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let key = Data(SHA256.hash(data: Data(("MacPair/v1/" + normalize(code)).utf8)))
        sec_protocol_options_add_pre_shared_key(options, dispatchData(key),
                                               dispatchData(Data("MacPair-v1".utf8)))
        // Keep pairing attempts independent of the TLS session cache.
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 12
        let parameters = NWParameters(tls: tls, tcp: tcp)
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
    var isDirect: Bool { directInterface != nil }

    init?(_ result: NWBrowser.Result) {
        guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
        self.id = "\(name).\(type).\(domain)"
        self.name = name
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
    private var isReady = false
    var onReady: (() -> Void)?
    var onPacket: ((Packet) -> Void)?
    var onClosed: ((LocalizedMessage) -> Void)?
    var onPath: ((LocalizedMessage) -> Void)?
    var onRTT: ((Double) -> Void)?

    init(_ connection: NWConnection, callbackQueue: DispatchQueue = .main) {
        self.connection = connection
        self.callbackQueue = callbackQueue
    }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if CommandLine.arguments.contains("--trace") { print("TRACE NWConnection: \(state)") }
            switch state {
            case .ready:
                self.isReady = true
                self.deadline?.cancel()
                self.lastReceived = DispatchTime.now().uptimeNanoseconds
                self.reportPath(self.connection.currentPath)
                self.deliver { $0.onReady?() }
                self.receive()
                self.startHeartbeat()
            case .waiting(let error):
                // A wrong PSK can enter .waiting rather than .failed. It is a
                // terminal pairing failure, not a route worth retrying.
                if case .tls = error {
                    self.finish("Pairing failed. Check the code currently shown on the display Mac.")
                } else {
                    self.deliver { $0.onPath?("Waiting for network: \(error.localizedDescription)") }
                }
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
        guard body.count + 1 <= Wire.maximumPacket else { completion?(false); return }
        let framed = Wire.frame(kind, body)
        queue.async { [weak self] in
            guard let self, !self.isClosed, self.isReady else { completion?(false); return }
            self.connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                completion?(error == nil)
                if let error { self?.finish("Send failed: \(error.localizedDescription)") }
            })
        }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                self.lastReceived = DispatchTime.now().uptimeNanoseconds
                do {
                    for packet in try self.parser.append(data) {
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
