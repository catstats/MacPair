// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import AppKit
import SwiftUI
import VideoToolbox
import Security

private func expect(_ condition: @autoclosure () -> Bool, _ message: LocalizedMessage) throws {
    if !condition() { throw PairError.message(message) }
}
@MainActor
private final class DiscoveryProbe { var found = false }

private final class DecodeProbe {
    let done = DispatchSemaphore(value: 0)
    var width = 0
    var height = 0
    var red = 0
    var status: OSStatus = -1
}

enum DiagnosticTests {
    static func run() -> Never {
        setbuf(stdout, nil)
        do {
            try localization()
            print("PASS: English/Chinese UI messages, live interpolation and language restoration")
            try discoverySuggestions()
            print("PASS: nearby suggestion gating, trusted priority, stable identity, dismissal and manual reset")
            try framing()
            print("PASS: fragmented/coalesced TCP packets and invalid lengths")
            try handshakeValidation()
            print("PASS: session version, dimensions and mode validation")
            try mirrorDimensions()
            print("PASS: Mirror/Extend negotiation and aspect-preserving screen sizes")
            try retinaNegotiation()
            print("PASS: receiver logical/backing sizing, 1×/2× presets and tampered-handshake rejection")
            try shortCodePairing()
            print("PASS: six-digit policy, expiry, lockout, SPAKE2 confirmation, tamper and replay rejection")
            try encryptedLoopback()
            print("PASS: real encrypted loopback, code-free remembered reconnect, revocation, downgrade and wrong-code rejection")
            try videoRoundtrip()
            try videoRoundtrip(width: 1230, height: 800)
            try videoRoundtrip(width: 2560, height: 1664)
            print("PASS: real H.264 encode/decode at 320×200, 1230×800 and Retina 2560×1664")
            print("Local tests passed. Two-Mac AWDL and ScreenCaptureKit capture are NOT covered by loopback.")
            exit(0)
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    private static func localization() throws {
        let original = UserDefaults.standard.object(forKey: L10n.preferenceKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: L10n.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: L10n.preferenceKey) }
        }
        L10n.setLanguage(.english)
        let path: LocalizedMessage = "Network path: \("awdl0")"
        let reason: LocalizedMessage = "Connection ended"
        let reconnect: LocalizedMessage = "\(reason) Waiting for the host to reconnect."
        try expect(path.localized == "Network path: awdl0", "English interpolation failed")
        L10n.setLanguage(.chinese)
        try expect(L("Test connection") == "测试直连" && L("Language") == "语言", "Chinese controls failed")
        try expect(path.localized == "网络路径：awdl0", "Chinese interpolation failed")
        try expect(reconnect.localized == "连接已结束。正在等待主机重新连接。", "Nested message translation failed")
        L10n.setLanguage(.english)
        try expect(reconnect.localized == "Connection ended Waiting for the host to reconnect.", "Switching back to English failed")
    }
    private static func discoverySuggestions() throws {
        let local = "self", first = "display-a", known = "display-b"
        let candidates = [
            DiscoveryCandidate(deviceID: local, name: "This Mac", direct: true, trusted: true),
            DiscoveryCandidate(deviceID: nil, name: "Missing identity", direct: true, trusted: false),
            DiscoveryCandidate(deviceID: "lan", name: "LAN only", direct: false, trusted: true),
            DiscoveryCandidate(deviceID: first, name: "A", direct: true, trusted: false),
            DiscoveryCandidate(deviceID: known, name: "B", direct: true, trusted: true)]
        var policy = DiscoverySuggestions()
        func pick(_ value: DiscoverySuggestions, enabled: Bool = true, host: Bool = true,
                  busy: Bool = false, editing: Bool = false) -> String? {
            value.next(in: candidates, localID: local, enabled: enabled, host: host,
                busy: busy, editingCode: editing)
        }
        try expect(pick(policy) == known, "Remembered displays should be offered first")
        try expect(pick(policy, enabled: false) == nil && pick(policy, host: false) == nil
            && pick(policy, busy: true) == nil && pick(policy, editing: true) == nil,
            "Suggestions ignored disabled/receiver/session/editing state")
        policy.didOffer(known)
        try expect(pick(policy) == first, "Presented stable identities were offered again")
        policy.didOffer(first)
        try expect(pick(policy) == nil, "Self, LAN-only or unidentified peers triggered a suggestion")
        let renamed = [DiscoveryCandidate(deviceID: known, name: "A different name", direct: true, trusted: true)]
        try expect(policy.next(in: renamed, localID: local, enabled: true, host: true, busy: false, editingCode: false) == nil,
                   "Renaming bypassed suggestion suppression")
        policy.reset(); policy.pause()
        try expect(pick(policy) == nil, "Dismissed cards kept interrupting")
        policy.reset()
        try expect(pick(policy) == known, "An explicit new search did not restore suggestions")
    }

    private static func framing() throws {
        let payload = Data((0..<4096).map { UInt8($0 % 251) })
        let combined = Wire.frame(.hello, Data("hello".utf8)) + Wire.frame(.video, payload) + Wire.frame(.ready)
        for strideSize in [1, 3, 4, 5, 37, combined.count] {
            var parser = PacketParser()
            var packets: [Packet] = []
            for start in stride(from: 0, to: combined.count, by: strideSize) {
                packets += try parser.append(Data(combined[start..<min(start + strideSize, combined.count)]))
            }
            try expect(packets.count == 3 && packets[0].kind == .hello && packets[1].body == payload && packets[2].body.isEmpty,
                       "分片/合包解析不正确")
        }
        for bytes: Data in [Data([0,0,0,0]), Data([255,255,255,255]), Data([0,0,0,1,255])] {
            var parser = PacketParser()
            var rejected = false
            do { _ = try parser.append(bytes) } catch { rejected = true }
            try expect(rejected, "无效数据包未被拒绝")
        }
    }
    private static func handshakeValidation() throws {
        let hello = SessionHello(version: Wire.version, mode: "extend", width: 1280, height: 800, fps: 30)
        try hello.validate()
        let decoded = try JSONDecoder().decode(SessionHello.self, from: JSONEncoder().encode(hello))
        try expect(decoded == hello, "会话编码失败")
        for invalid in [
            SessionHello(version: Wire.version + 1, mode: "extend", width: 1280, height: 800, fps: 30),
            SessionHello(version: Wire.version, mode: "extend", width: 1281, height: 800, fps: 30),
            SessionHello(version: Wire.version, mode: "unknown", width: 1280, height: 800, fps: 30)
        ] {
            var rejected = false
            do { try invalid.validate() } catch { rejected = true }
            try expect(rejected, "不兼容会话未被拒绝")
        }
        try expect(PeerNetwork.normalize("024-681") == "024681", "配对码规范化失败")
        try expect(PeerNetwork.normalize(PeerNetwork.newCode()).count == 6, "配对码长度失败")
    }
    private static func mirrorDimensions() throws {
        for (width, height, expectedWidth, expectedHeight) in [
            (2560, 1664, 1230, 800),
            (2880, 1800, 1280, 800),
            (1080, 1920, 450, 800),
            (5120, 1440, 1280, 360)
        ] {
            let size = try MirrorSizing.dimensions(width: width, height: height)
            try expect(size.width == expectedWidth && size.height == expectedHeight, "Mirror aspect-ratio sizing failed")
            let hello = SessionHello(version: Wire.version, mode: "mirror", width: size.width, height: size.height, fps: 30)
            try hello.validate()
            try expect(hello.isVideo, "Mirror session was not recognized as video")
            let decoded = try JSONDecoder().decode(SessionHello.self, from: JSONEncoder().encode(hello))
            try expect(decoded == hello, "Mirror handshake roundtrip failed")
        }
        try expect(SessionHello(version: Wire.version, mode: "extend", width: 1280, height: 800, fps: 30).isVideo,
                   "Extend session was not recognized as video")
        try expect(!SessionHello(version: Wire.version, mode: "diagnostic", width: 1280, height: 800, fps: 30).isVideo,
                   "A diagnostic session must not receive video")
        for invalid in [
            SessionHello(version: Wire.version, mode: "mirror", width: 1231, height: 800, fps: 30),
            SessionHello(version: Wire.version, mode: "mirror", width: 1280, height: 8, fps: 30),
            SessionHello(version: Wire.version, mode: "mirror", width: 2048, height: 800, fps: 30)
        ] {
            var rejected = false
            do { try invalid.validate() } catch { rejected = true }
            try expect(rejected, "Invalid Mirror dimensions were accepted")
        }
        var rejected = false
        do { _ = try MirrorSizing.dimensions(width: 0, height: 100) } catch { rejected = true }
        try expect(rejected, "An unavailable source screen was accepted")
    }
    private static func retinaNegotiation() throws {
        func info(_ width: Int, _ height: Int, _ scale: Int) -> ReceiverDisplayInfo {
            let geometry = DisplayGeometry(logicalWidth: width, logicalHeight: height,
                backingWidth: width * scale, backingHeight: height * scale, scale: scale)
            return ReceiverDisplayInfo(name: "Fixture", screen: geometry, viewport: geometry)
        }
        let retina = info(1280, 832, 2)
        for (preset, expected) in [
            (ResolutionPreset.recommended, VirtualCanvas(width: 1280, height: 832, scale: 2)),
            (.largerText, VirtualCanvas(width: 1024, height: 666, scale: 2)),
            (.moreSpace, VirtualCanvas(width: 1600, height: 1040, scale: 2))
        ] {
            let request = SessionHello(version: Wire.version, mode: "extend", width: 1280, height: 800, fps: 30, resolution: preset)
            let response = try request.negotiated(for: retina)
            try expect(response.canvas == expected && response.width == expected.pixelWidth && response.height == expected.pixelHeight,
                       "Retina preset lost logical/backing dimensions")
            let decoded = try JSONDecoder().decode(SessionHello.self, from: JSONEncoder().encode(response))
            try decoded.validateResponse(to: request)
            let tampered = SessionHello(version: Wire.version, mode: "extend", width: 1280, height: 800,
                fps: 30, resolution: preset, receiver: retina, canvas: expected)
            var rejected = false
            do { try tampered.validateResponse(to: request) } catch { rejected = true }
            try expect(rejected, "A response with mismatched encoded pixels was accepted")
        }
        for display in [info(1920, 1080, 1), info(901, 1601, 1), info(1720, 720, 2)] {
            let canvas = try ResolutionSizing.canvas(for: display, preset: .recommended)
            try expect(abs(Double(canvas.width) / Double(canvas.height)
                - Double(display.viewport.logicalWidth) / Double(display.viewport.logicalHeight)) < 0.003,
                "Receiver aspect ratio was not preserved")
            try expect(canvas.pixelWidth % 2 == 0 && canvas.pixelHeight % 2 == 0, "H.264 needs even dimensions")
        }
        let screen = DisplayGeometry(logicalWidth: 1280, logicalHeight: 864, backingWidth: 2560, backingHeight: 1728, scale: 2)
        let notched = ReceiverDisplayInfo(name: "Notched screen", screen: screen, viewport: retina.viewport)
        let notchCanvas = try ResolutionSizing.canvas(for: notched, preset: .recommended)
        try expect(notchCanvas.height == 832, "Fullscreen content must use its measured viewport, not the notch area")
        for mode in ["mirror", "diagnostic"] {
            let request = SessionHello(version: Wire.version, mode: mode, width: 1230, height: 800, fps: 30)
            let response = try request.negotiated(for: retina)
            try response.validateResponse(to: request)
            try expect(response.width == 1230 && response.height == 800 && response.canvas == nil,
                       "Mirror/diagnostic dimensions changed during receiver negotiation")
        }
        for display in [info(1280, 832, 3), info(8192, 8192, 2),
                        ReceiverDisplayInfo(name: "Bad backing", screen: screen,
                            viewport: DisplayGeometry(logicalWidth: 1280, logicalHeight: 832,
                                backingWidth: 1280, backingHeight: 832, scale: 2))] {
            var rejected = false
            do { _ = try ResolutionSizing.canvas(for: display, preset: .moreSpace) } catch { rejected = true }
            try expect(rejected, "Invalid or oversized receiver dimensions were accepted")
        }
        let legacy = Data(#"{"version":1,"mode":"extend","width":1280,"height":800,"fps":30}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionHello.self, from: legacy)
        var rejected = false
        do { try decoded.validateRequest() } catch { rejected = true }
        try expect(rejected, "A legacy peer must be told to update")
    }
    private static func shortCodePairing() throws {
        for _ in 0..<1000 { try expect(PairingCode.isValid(PairingCode.generate()), "Generated an invalid numeric code") }
        for valid in ["000000", "000123", "024 681", "024-681"] {
            try expect(PairingCode.isValid(valid), "A valid six-digit code was rejected")
        }
        for invalid in ["", "12345", "1234567", "123a56", "１２３４５６", "٠١٢٣٤٥"] {
            try expect(!PairingCode.isValid(invalid), "A non-ASCII or incorrectly sized code was accepted")
        }
        try expect(PairingCode.normalize(" 000-123 ") == "000123", "Leading zeroes were lost")
        var gate = PairingGate()
        try expect(gate.issue(at: 100) && gate.accepts(at: 399.9) && !gate.accepts(at: 400), "Five-minute expiry failed")
        try expect(gate.issue(at: 401), "Cannot explicitly issue a fresh code")
        for attempt in 1...5 {
            let blocked = gate.failed(at: 402 + Double(attempt))
            try expect(blocked == (attempt == 5), "Global pairing attempt budget failed")
        }
        gate.invalidate() // Stopping/restarting must not bypass the cooldown.
        try expect(!gate.issue(at: 420) && !gate.accepts(at: 420), "Restart bypassed the pairing cooldown")
        try expect(gate.issue(at: 437) && gate.failures == 0, "Cooldown did not expire")
        gate.consume()
        try expect(!gate.accepts(at: 438), "A successfully used code stayed valid")
        let store = TrustStore(memoryOnly: true)
        let peer = PeerIdentity(id: UUID().uuidString, name: "Fixture Mac")
        let fixture = TrustedDevice(id: String(repeating: "a", count: 32), peer: peer,
            secret: Data(repeating: 42, count: 32), createdAt: Date())
        try store.save(fixture)
        let loaded = try store.credential(forPeer: peer.id)
        try expect(loaded?.secret == fixture.secret, "Trusted-device storage failed")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as! [String: Any]
        try expect(json["code"] == nil && json["pin"] == nil, "A PIN was included in the persisted credential")
        try store.forgetPeer(peer.id)
        let forgotten = try store.credential(id: fixture.id)
        try expect(forgotten == nil, "Forgetting did not remove the pairing secret")

        let host = try PasswordExchange(host: true, code: "024681")
        let display = try PasswordExchange(host: false, code: "024681")
        let hostKeys = try host.finish(peerMessage: display.message)
        let displayKeys = try display.finish(peerMessage: host.message)
        try expect(hostKeys.verifyPeer(displayKeys.localProof) && displayKeys.verifyPeer(hostKeys.localProof), "SPAKE2 mutual confirmation failed")
        try expect(!hostKeys.verifyPeer(hostKeys.localProof), "Reflected confirmation was accepted")
        var rejected = false
        do { _ = try host.finish(peerMessage: display.message) } catch { rejected = true }
        try expect(rejected, "A SPAKE2 context was reused")
        let wrongHost = try PasswordExchange(host: true, code: "024680")
        let correctDisplay = try PasswordExchange(host: false, code: "024681")
        let wrongKeys = try wrongHost.finish(peerMessage: correctDisplay.message)
        let correctKeys = try correctDisplay.finish(peerMessage: wrongHost.message)
        try expect(!correctKeys.verifyPeer(wrongKeys.localProof) && !wrongKeys.verifyPeer(correctKeys.localProof), "Wrong PIN produced a valid confirmation")
        let sameRoleA = try PasswordExchange(host: true, code: "024681")
        let sameRoleB = try PasswordExchange(host: true, code: "024681")
        let sameRoleKeysA = try sameRoleA.finish(peerMessage: sameRoleB.message)
        let sameRoleKeysB = try sameRoleB.finish(peerMessage: sameRoleA.message)
        try expect(!sameRoleKeysA.verifyPeer(sameRoleKeysB.localProof), "Two hosts authenticated as opposite roles")

        let sender = PacketCipher(keys: hostKeys), receiver = PacketCipher(keys: displayKeys)
        let empty = try sender.seal(.hello, Data())
        let first = try receiver.open(empty)
        try expect(first.kind == .hello && first.body.isEmpty, "Empty encrypted payload roundtrip failed")
        rejected = false
        do { _ = try receiver.open(empty) } catch { rejected = true }
        try expect(rejected, "A replayed encrypted record was accepted")
        let body = Data("MacPair secret application payload".utf8)
        let record = try sender.seal(.video, body)
        try expect(record.range(of: body) == nil, "Plain application payload appeared on the wire")
        var altered = record; altered[altered.count - 1] ^= 1
        rejected = false
        do { _ = try receiver.open(altered) } catch { rejected = true }
        try expect(rejected, "A modified authentication tag was accepted")
        let restored = try receiver.open(record)
        try expect(restored.kind == .video && restored.body == body, "Authenticated data did not roundtrip")
        let pending1 = try sender.seal(.format, Data([1])), pending2 = try sender.seal(.format, Data([2]))
        rejected = false
        do { _ = try receiver.open(pending2) } catch { rejected = true }
        try expect(rejected, "An out-of-order record was accepted")
        _ = try receiver.open(pending1); _ = try receiver.open(pending2)
    }
    private static func encryptedLoopback() throws {
        let callbackQueue = DispatchQueue(label: "MacPair.tests")
        let listening = DispatchSemaphore(value: 0)
        let reply = DispatchSemaphore(value: 0)
        let wrongClosed = DispatchSemaphore(value: 0)
        let code = "024681"
        let hostIdentity = PeerIdentity(id: "00000000-0000-0000-0000-000000000001", name: "Test host")
        let displayIdentity = PeerIdentity(id: "00000000-0000-0000-0000-000000000002", name: "Test display")
        let payload = Data((0..<(512 * 1024)).map { UInt8($0 % 251) })
        let receiverTrust = TrustStore(memoryOnly: true)
        let listener = try NWListener(using: PeerNetwork.parameters(), on: .any)
        var accepted: [PeerLink] = []
        var receivedCorrectly = false
        var encryptedCorrectly = false
        var wrongWasReady = false
        listener.stateUpdateHandler = { state in if case .ready = state { listening.signal() } }
        listener.newConnectionHandler = { connection in
            let server = PeerLink(connection, host: false, code: code, identity: displayIdentity,
                lookupTrusted: { try receiverTrust.credential(id: $0) }, callbackQueue: callbackQueue)
            accepted.append(server)
            server.onReady = { [weak server] in
                if let credential = server?.authenticatedCredential { try? receiverTrust.save(credential) }
            }
            server.onPacket = { [weak server] packet in
                if packet.kind == .hello { server?.send(.ready, packet.body) }
            }
            server.start()
        }
        listener.start(queue: callbackQueue)
        defer {
            listener.cancel()
            callbackQueue.sync { accepted.forEach { $0.cancel() } }
        }
        try expect(listening.wait(timeout: .now() + 5) == .success, "测试监听器未就绪")
        guard let port = listener.port else { throw PairError.message("测试监听器没有端口") }
        let client = PeerLink(NWConnection(host: "127.0.0.1", port: port,
            using: PeerNetwork.parameters()), host: true, code: code, identity: hostIdentity, expectedPeer: displayIdentity, callbackQueue: callbackQueue)
        client.onReady = { [weak client] in
            encryptedCorrectly = client?.isReady == true
            client?.send(.hello, payload)
        }
        client.onPacket = { packet in receivedCorrectly = packet.kind == .ready && packet.body == payload; reply.signal() }
        client.start()
        defer { client.cancel() }
        try expect(reply.wait(timeout: .now() + 8) == .success && receivedCorrectly && encryptedCorrectly, "Secure pairing or encrypted payload transfer failed")

        guard let saved = client.authenticatedCredential else { throw PairError.message("No saved pairing material") }
        try saved.validate()
        try expect(saved.peer.id == displayIdentity.id && saved.secret.count == 32, "Saved pairing was not bound to its peer")
        let hostTrust = TrustStore(memoryOnly: true)
        try hostTrust.save(saved)
        let impostor = PeerIdentity(id: UUID().uuidString, name: displayIdentity.name)
        let wrongNameLookup = try hostTrust.credential(forPeer: impostor.id)
        try expect(wrongNameLookup == nil, "A device with the same name inherited trust")
        let downgradeClosed = DispatchSemaphore(value: 0)
        client.onClosed = { _ in downgradeClosed.signal() }
        client.connection.send(content: Wire.frame(.hello, Data("unencrypted injection".utf8)), completion: .idempotent)
        try expect(downgradeClosed.wait(timeout: .now() + 5) == .success, "Plaintext injection was accepted after pairing")

        let resumed = DispatchSemaphore(value: 0)
        var resumedOK = false
        let reconnect = PeerLink(NWConnection(host: "127.0.0.1", port: port,
            using: PeerNetwork.parameters()), host: true, code: nil, identity: hostIdentity,
            expectedPeer: displayIdentity, trusted: saved, callbackQueue: callbackQueue)
        reconnect.onReady = { [weak reconnect] in reconnect?.send(.hello, payload) }
        reconnect.onPacket = { [weak reconnect] packet in
            resumedOK = reconnect?.isResuming == true && packet.kind == .ready && packet.body == payload
            resumed.signal()
        }
        reconnect.start()
        defer { reconnect.cancel() }
        try expect(resumed.wait(timeout: .now() + 8) == .success && resumedOK, "Remembered reconnect without any PIN failed")
        reconnect.cancel()
        try receiverTrust.forget(id: saved.id)
        let revokedClosed = DispatchSemaphore(value: 0)
        var revokedWasReady = false
        let revoked = PeerLink(NWConnection(host: "127.0.0.1", port: port,
            using: PeerNetwork.parameters()), host: true, code: nil, identity: hostIdentity,
            expectedPeer: displayIdentity, trusted: saved, callbackQueue: callbackQueue)
        revoked.onReady = { revokedWasReady = true; revokedClosed.signal() }
        revoked.onClosed = { _ in revokedClosed.signal() }
        revoked.start()
        defer { revoked.cancel() }
        try expect(revokedClosed.wait(timeout: .now() + 8) == .success && !revokedWasReady, "A forgotten Mac reconnected without a new code")

        let wrong = PeerLink(NWConnection(host: "127.0.0.1", port: port,
            using: PeerNetwork.parameters()), host: true, code: "024680", identity: hostIdentity, expectedPeer: displayIdentity, callbackQueue: callbackQueue)
        wrong.onReady = { wrongWasReady = true; wrongClosed.signal() }
        wrong.onClosed = { _ in wrongClosed.signal() }
        wrong.start()
        defer { wrong.cancel() }
        let wrongResult = wrongClosed.wait(timeout: .now() + 8)
        try expect(wrongResult == .success && !wrongWasReady, "Wrong six-digit code was not rejected")
    }
    private static func videoRoundtrip(width: Int = 320, height: Int = 200) throws {
        let ready = DispatchSemaphore(value: 0)
        var configuration: Data?
        var video: Data?
        var encodeError: LocalizedMessage?
        let encoder = try H264Encoder(width: width, height: height, fps: 30)
        defer { encoder.stop() }
        encoder.onOutput = { format, data, error in
            configuration = format; video = data; encodeError = error; ready.signal()
        }
        var image: CVPixelBuffer?
        try expect(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image) == kCVReturnSuccess,
            "无法创建测试像素缓冲")
        guard let image else { throw PairError.message("测试画面不存在") }
        CVPixelBufferLockBaseAddress(image, [])
        if let base = CVPixelBufferGetBaseAddress(image) {
            let pointer = base.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(image)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * row + x * 4
                    pointer[offset] = 32; pointer[offset + 1] = 64
                    pointer[offset + 2] = 210; pointer[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(image, [])
        try encoder.encode(image, forceKeyframe: true)
        try expect(ready.wait(timeout: .now() + 5) == .success, "H.264 编码超时")
        if let encodeError { throw PairError.message(encodeError) }
        guard let configuration, let video else { throw PairError.message("没有 H.264 输出") }
        let samples = H264Samples()
        try samples.configure(configuration, expectedWidth: width, expectedHeight: height)
        var mismatchRejected = false
        do { try samples.configure(configuration, expectedWidth: width + 2, expectedHeight: height) }
        catch { mismatchRejected = true }
        try expect(mismatchRejected, "A stream with dimensions different from its handshake was accepted")
        let sample = try samples.sample(video)
        let probe = DecodeProbe()
        var record = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { context, _, status, _, image, _, _ in
            guard let context else { return }
            let probe = Unmanaged<DecodeProbe>.fromOpaque(context).takeUnretainedValue()
            probe.status = status
            if let image {
                probe.width = CVPixelBufferGetWidth(image)
                probe.height = CVPixelBufferGetHeight(image)
                CVPixelBufferLockBaseAddress(image, .readOnly)
                if let pointer = CVPixelBufferGetBaseAddress(image)?.assumingMemoryBound(to: UInt8.self) {
                    probe.red = Int(pointer[2])
                }
                CVPixelBufferUnlockBaseAddress(image, .readOnly)
            }
            probe.done.signal()
        }, decompressionOutputRefCon: Unmanaged.passUnretained(probe).toOpaque())
        var decoder: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
            formatDescription: samples.format!, decoderSpecification: nil,
            imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary,
            outputCallback: &record, decompressionSessionOut: &decoder)
        try expect(status == noErr && decoder != nil, "无法创建真实 H.264 解码器")
        guard let decoder else { throw PairError.message("解码器为空") }
        defer { VTDecompressionSessionInvalidate(decoder) }
        try expect(VTDecompressionSessionDecodeFrame(decoder, sampleBuffer: sample, flags: [],
            frameRefcon: nil, infoFlagsOut: nil) == noErr, "解码提交失败")
        VTDecompressionSessionWaitForAsynchronousFrames(decoder)
        try expect(probe.done.wait(timeout: .now() + 5) == .success, "解码没有输出")
        try expect(probe.status == noErr && probe.width == width && probe.height == height && probe.red > 160,
                   "真实解码的尺寸或颜色不正确")
        var rejected = false
        do { _ = try samples.sample(Data([0,0,0,99,1])) } catch { rejected = true }
        try expect(rejected, "非法 AVCC 帧未被拒绝")
    }

    @MainActor
    static func pairingSmokeTest() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let hostID = PeerIdentity(id: UUID().uuidString, name: "Test main Mac")
            let displayID = PeerIdentity(id: UUID().uuidString, name: "Test display Mac")
            let hostStore = TrustStore(memoryOnly: true), displayStore = TrustStore(memoryOnly: true)
            let preferenceSuite = "local.macpair.prototype.test.discovery." + UUID().uuidString
            let preferences = UserDefaults(suiteName: preferenceSuite)!
            defer { preferences.removePersistentDomain(forName: preferenceSuite) }
            preferences.set(MacRole.receiver.rawValue, forKey: "MacPairRole")
            var model = AppModel(trustStore: displayStore, identity: displayID, preferences: preferences)
            @MainActor func waitFor(_ predicate: () -> Bool, _ message: LocalizedMessage) async throws {
                for _ in 0..<100 {
                    if predicate() { return }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                throw PairError.message(message)
            }
            @MainActor func client(code: String?, trusted: TrustedDevice? = nil, remember: Bool = true) throws -> PeerLink {
                guard let port = model.receivingPort else { throw PairError.message("No pairing test port") }
                let link = PeerLink(NWConnection(host: "127.0.0.1", port: port, using: PeerNetwork.parameters()),
                    host: true, code: code, identity: hostID, expectedPeer: displayID, trusted: trusted)
                link.onReady = { [weak link] in
                    guard let link, let credential = link.authenticatedCredential else { return }
                    if remember { try? hostStore.save(credential) }
                    link.send(.trustStatus, Data([remember ? 1 : 0]))
                }
                link.onPacket = { [weak link] packet in
                    if packet.kind == .trustStatus, let body = try? JSONEncoder().encode(SessionHello(
                        version: Wire.version, mode: "diagnostic", width: 1280, height: 800, fps: 30)) {
                        link?.send(.hello, body)
                    }
                }
                return link
            }
            do {
                try expect(model.role == .receiver, "The saved display role was not restored")
                model.startAutomaticBehavior()
                try await waitFor({ model.listening }, "The saved display role did not start waiting automatically")
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: PeerNetwork.serviceType, domain: nil),
                    using: PeerNetwork.discoveryParameters())
                let discovery = DiscoveryProbe()
                browser.browseResultsChangedHandler = { results, _ in
                    let found = results.compactMap(DiscoveredPeer.init).contains { $0.deviceIdentity?.id == displayID.id }
                    Task { @MainActor in discovery.found = found }
                }
                browser.start(queue: .main)
                do { try await waitFor({ discovery.found }, "Bonjour did not include the receiver's stable TXT identity") }
                catch { browser.cancel(); throw error }
                browser.cancel()
                print("PASS: actual Bonjour TXT discovery identifies the correct Mac")
                let originalCode = model.pairingCode
                let first = try client(code: originalCode)
                first.start()
                try await waitFor({ model.connected && model.rememberedSession }, "First pairing or mutual trust acknowledgement failed")
                try expect(model.pairingCode.isEmpty && !model.listening, "A successfully used code stayed available")
                let saved = try hostStore.credential(forPeer: displayID.id)
                guard let saved else { throw PairError.message("The first pairing was not remembered") }
                // Synthetic numbers reproduce the stale-statistics UI regression;
                // they are not a measured performance result.
                model.rtt = "7.6 ms"; model.totalFrames = 455; model.fps = 30
                model.endSession()
                try expect(model.lastSession?.rtt == "7.6 ms" && model.lastSession?.frames == 455,
                           "Disconnect lost the previous session summary")
                try expect(model.rtt == "—" && model.fps == 0 && model.totalFrames == 0
                    && model.path.localized == L("Not connected"), "Disconnected state retained live statistics")
                first.cancel()
                try await waitFor({ model.listening && !model.occupied }, "A fresh waiting session was not created")
                print("PASS: disconnect archives the last session and clears all live metrics")
                try expect(PairingCode.isValid(model.pairingCode) && model.pairingCode != originalCode, "The old six-digit code was reused")
                model.stopAll()
                try await waitFor({ !model.occupied }, "First receiver did not stop")

                // Simulate reopening the app with the same persistent credential store.
                model = AppModel(trustStore: displayStore, identity: displayID)
                model.role = .receiver
                try expect(model.trustedDevices.count == 1, "Paired device was lost across app-model restart")
                model.listen()
                try await waitFor({ model.listening }, "Restarted receiver did not start")
                model.expirePairingCode()
                try expect(model.listening && model.pairingCode.isEmpty, "Code expiry hid trusted-device availability")
                let resumed = try client(code: nil, trusted: saved)
                resumed.start()
                try await waitFor({ model.connected && model.rememberedSession }, "Remembered pairing still required a code")
                try expect(resumed.isResuming, "Reconnect did not use the saved credential")
                resumed.cancel()
                try await waitFor({ model.listening && !model.occupied }, "Receiver did not return to waiting")
                guard let summary = model.trustedDevices.first else { throw PairError.message("No device to forget") }
                model.forgetDevice(summary)
                try expect(model.trustedDevices.isEmpty, "Forget did not remove the trusted device")

                var revokedClosed = false, unauthorized = false
                let revoked = try client(code: nil, trusted: saved)
                revoked.onReady = { unauthorized = true }
                revoked.onClosed = { _ in revokedClosed = true }
                revoked.start()
                try await waitFor({ revokedClosed && !model.occupied }, "Revoked credential did not close")
                try expect(!unauthorized && !model.connected, "A forgotten Mac was allowed to reconnect")
                let badCode = String(format: "%06d", (Int(model.pairingCode)! + 1) % 1_000_000)
                // The revoked credential was failure one; four bad PINs exhaust
                // the single global budget (changing auth modes cannot reset it).
                for _ in 0..<4 {
                    var closed = false
                    let wrong = try client(code: badCode)
                    wrong.onReady = { unauthorized = true }
                    wrong.onClosed = { _ in closed = true }
                    wrong.start()
                    try await waitFor({ closed && !model.occupied }, "Failed pairing did not finish")
                    wrong.cancel()
                }
                try expect(!unauthorized && model.pairingCoolingDown && !model.listening && model.pairingCode.isEmpty,
                           "The five-attempt global lockout did not activate")
                model.listen()
                try expect(!model.listening, "Wait for connection bypassed cooldown")
                model.stopAll()
                print("PASS: actual AppModel first pairing, one-time code, restart without PIN, Forget revocation and five-attempt cooldown")

                let oneShotStore = TrustStore(memoryOnly: true)
                model = AppModel(trustStore: oneShotStore, identity: displayID)
                model.role = .receiver
                model.listen()
                try await waitFor({ model.listening }, "One-session receiver did not start")
                let oneShot = try client(code: model.pairingCode, remember: false)
                oneShot.start()
                try await waitFor({ model.connected }, "One-session pairing failed")
                let incomplete = try oneShotStore.all()
                try expect(!model.rememberedSession && incomplete.isEmpty, "A half-saved pairing was kept without peer acknowledgement")
                oneShot.cancel()
                model.stopAll()
                print("PASS: declined/failed credential saving keeps the session encrypted and removes half-saved trust")

                preferences.set(MacRole.host.rawValue, forKey: "MacPairRole")
                model = AppModel(trustStore: TrustStore(memoryOnly: true), identity: hostID, preferences: preferences)
                model.startAutomaticBehavior()
                try await waitFor({ model.browsing }, "Host did not start discovery automatically")
                model.automaticDiscovery = false
                model.automaticDiscoveryChanged()
                try expect(!model.browsing && model.suggestedDeviceID == nil, "Discovery opt-out left browsing/cards active")
                model.stopAll()
                try await waitFor({ !model.occupied }, "Host did not finish stopping")
                model = AppModel(trustStore: TrustStore(memoryOnly: true), identity: hostID, preferences: preferences)
                try expect(!model.automaticDiscovery && model.role == .host, "Role/discovery preferences were not restored")
                model.startAutomaticBehavior()
                try await waitFor({ !model.occupied }, "Opted-out host did not finish startup")
                try expect(!model.browsing, "Startup ignored the discovery opt-out")
                model.role = .receiver
                model.activateRole()
                try await waitFor({ model.listening }, "Switching to Display Mac did not start waiting")
                try expect(preferences.string(forKey: "MacPairRole") == MacRole.receiver.rawValue,
                           "Selecting a role did not persist it")
                model.stopAll()
                try await waitFor({ !model.occupied }, "Role automation did not stop")
                model.startAutomaticBehavior()
                try expect(!model.listening && !model.browsing, "Repeated window appearance overrode an explicit Stop")
                print("PASS: automatic host discovery, restored display waiting, persisted opt-out and explicit Stop")
                preferences.removePersistentDomain(forName: preferenceSuite)
                exit(0)
            } catch {
                model.stopAll()
                preferences.removePersistentDomain(forName: preferenceSuite)
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        app.run()
        exit(1)
    }

    static func keychainReadProbe() -> Never {
        do {
            let args = CommandLine.arguments
            guard args.count == 5, args[2].hasPrefix("local.macpair.prototype.test."),
                  UUID(uuidString: String(args[2].dropFirst("local.macpair.prototype.test.".count))) != nil else {
                throw PairError.message("Invalid scoped Keychain probe")
            }
            let record = try TrustStore(service: args[2]).credential(id: args[3])
            try expect(record?.peer.id == args[4] && record?.secret == Data(repeating: 0x73, count: 32),
                "A second process could not read the persisted test credential")
            print("PASS: a fresh MacPair process read the scoped persisted credential")
            exit(0)
        } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func keychainSmokeTest() -> Never {
        do {
            let namespace = "local.macpair.prototype.test." + UUID().uuidString
            let store = TrustStore(service: namespace)
            let record = TrustedDevice(id: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()),
                peer: PeerIdentity(id: UUID().uuidString, name: "Temporary MacPair test"),
                secret: Data(repeating: 0x73, count: 32), createdAt: Date())
            defer { try? store.forget(id: record.id) }
            try store.save(record)
            let loaded = try store.credential(forPeer: record.peer.id)
            try expect(loaded?.secret == record.secret && loaded?.id == record.id, "Real Keychain roundtrip failed")
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--keychain-read-probe", namespace, record.id, record.peer.id]
            let finished = DispatchSemaphore(value: 0)
            child.terminationHandler = { _ in finished.signal() }
            try child.run()
            guard finished.wait(timeout: .now() + 8) == .success else {
                child.terminate()
                throw PairError.message("Keychain persistence probe timed out")
            }
            try expect(child.terminationStatus == 0, "Persisted credential was not available after process restart")
            try store.forget(id: record.id)
            let removed = try store.credential(id: record.id)
            try expect(removed == nil, "Temporary Keychain record was not deleted")
            print("PASS: scoped real macOS Keychain save/read/remove; no user pairing records accessed")
            exit(0)
        } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    @MainActor
    static func nearbyPanelSmokeTest() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let previouslyActive = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { @MainActor in
            do {
                let panel = NearbyDisplayPanel.make(remembered: true,
                    content: NearbyDisplayCard(name: "MacPair UI test", remembered: true,
                        mode: .constant(.extend), code: .constant(""), connect: {}, dismiss: {}))
                panel.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(300))
                let visible = panel.isVisible
                let tookFocus = panel.isKeyWindow || panel.isMainWindow
                    || NSWorkspace.shared.frontmostApplication?.processIdentifier != previouslyActive
                panel.close()
                try expect(visible && !tookFocus, "The discovery panel was hidden or took focus")
                try expect(!panel.isVisible, "The discovery panel did not close")
                print("PASS: real native discovery panel appears without changing foreground focus and closes cleanly")
                exit(0)
            } catch {
                fputs("FAIL: " + error.localizedDescription + "\n", stderr)
                exit(1)
            }
        }
        app.run()
        exit(1)
    }

    @MainActor
    static func receiverSmokeTest() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let model = AppModel()
        Task { @MainActor in
            do {
                let info = try await model.prepareViewer()
                let canvas = try ResolutionSizing.canvas(for: info, preset: .recommended)
                try expect(canvas.pixelWidth == info.viewport.backingWidth
                    && canvas.pixelHeight == info.viewport.backingHeight,
                    "Default must match the actual full-screen backing dimensions")
                print("PASS: actual AppKit full-screen receiver: screen \(info.screen.logicalWidth)×\(info.screen.logicalHeight) pt, viewport \(info.viewport.logicalWidth)×\(info.viewport.logicalHeight) pt, backing \(info.viewport.backingWidth)×\(info.viewport.backingHeight) px @\(info.viewport.scale)×")
                model.endSession()
                // Let AppKit finish closing its full-screen window before exit.
                try await Task.sleep(nanoseconds: 500_000_000)
                exit(0)
            } catch {
                model.endSession()
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        app.run()
        exit(1)
    }

    @MainActor
    static func displaySmokeTest() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let testSerial = UInt32.random(in: 0x4D50A000...0x4D50E000)
                for (index, canvas) in [VirtualCanvas(width: 1280, height: 800, scale: 1),
                                        VirtualCanvas(width: 1280, height: 832, scale: 2),
                                        VirtualCanvas(width: 1024, height: 666, scale: 2),
                                        VirtualCanvas(width: 1600, height: 1040, scale: 2)].enumerated() {
                    // Separate identities cannot collide with the user's live session.
                    var screen: VirtualScreen? = try VirtualScreen(width: canvas.width, height: canvas.height,
                        scale: canvas.scale, serial: testSerial + UInt32(index))
                    let id = screen!.id
                    do {
                        try await screen!.arrange()
                        try expect(VirtualScreen.isOnline(id) && CGDisplayIsInMirrorSet(id) == 0, "虚拟扩展屏未上线")
                        guard let mode = CGDisplayCopyDisplayMode(id) else { throw PairError.message("No current display mode") }
                        try expect(mode.width == canvas.width && mode.height == canvas.height
                            && mode.pixelWidth == canvas.pixelWidth && mode.pixelHeight == canvas.pixelHeight,
                            "Virtual display logical/backing dimensions do not match")
                        // Allow WindowServer's delayed saved-mode restore and the mode monitor to run.
                        try await Task.sleep(nanoseconds: 2_300_000_000)
                        guard let settled = CGDisplayCopyDisplayMode(id) else { throw PairError.message("Display mode disappeared") }
                        try expect(settled.width == canvas.width && settled.pixelWidth == canvas.pixelWidth,
                                   "The virtual screen reverted to a non-Retina mode")
                        print("PASS: real extended display \(canvas.width)×\(canvas.height) pt @\(canvas.scale)× = \(canvas.pixelWidth)×\(canvas.pixelHeight) px")
                    } catch { screen?.close(); throw error }
                    screen?.close()
                    screen = nil
                    for _ in 0..<30 {
                        if !VirtualScreen.isOnline(id) { break }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    try expect(!VirtualScreen.isOnline(id), "虚拟显示器未被移除")
                    print("PASS: virtual display \(id) removed")
                }
                exit(0)
            } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        app.run()
        exit(1)
    }
}

@main
enum MacPairLauncher {
    @MainActor
    static func main() {
        setbuf(stdout, nil)
        if CommandLine.arguments.contains("--self-test") { DiagnosticTests.run() }
        if CommandLine.arguments.contains("--display-smoke-test") { DiagnosticTests.displaySmokeTest() }
        if CommandLine.arguments.contains("--pairing-smoke-test") { DiagnosticTests.pairingSmokeTest() }
        if CommandLine.arguments.contains("--keychain-read-probe") { DiagnosticTests.keychainReadProbe() }
        if CommandLine.arguments.contains("--keychain-smoke-test") { DiagnosticTests.keychainSmokeTest() }
        if CommandLine.arguments.contains("--nearby-panel-smoke-test") { DiagnosticTests.nearbyPanelSmokeTest() }
        if CommandLine.arguments.contains("--receiver-smoke-test") { DiagnosticTests.receiverSmokeTest() }
        if CommandLine.arguments.contains("--mirror-smoke-test") { MirrorCaptureCheck.run() }
        MacPairApp.main()
    }
}
