// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import AppKit
import VideoToolbox
import Security

private func expect(_ condition: @autoclosure () -> Bool, _ message: LocalizedMessage) throws {
    if !condition() { throw PairError.message(message) }
}
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
            try framing()
            print("PASS: fragmented/coalesced TCP packets and invalid lengths")
            try handshakeValidation()
            print("PASS: session version, dimensions and mode validation")
            try mirrorDimensions()
            print("PASS: Mirror/Extend negotiation and aspect-preserving screen sizes")
            try retinaNegotiation()
            print("PASS: receiver logical/backing sizing, 1×/2× presets and tampered-handshake rejection")
            try encryptedLoopback()
            print("PASS: real TLS-PSK loopback, 512 KB payload and wrong-code rejection")
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
        try expect(PeerNetwork.normalize("abcd-efgh jklm") == "ABCDEFGHJKLM", "配对码规范化失败")
        try expect(PeerNetwork.normalize(PeerNetwork.newCode()).count == 12, "配对码长度失败")
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
    private static func encryptedLoopback() throws {
        let callbackQueue = DispatchQueue(label: "MacPair.tests")
        let listening = DispatchSemaphore(value: 0)
        let reply = DispatchSemaphore(value: 0)
        let wrongClosed = DispatchSemaphore(value: 0)
        let code = "ABCD-EFGH-JKLM"
        let payload = Data((0..<(512 * 1024)).map { UInt8($0 % 251) })
        let listener = try NWListener(using: PeerNetwork.parameters(code: code), on: .any)
        var accepted: [PeerLink] = []
        var receivedCorrectly = false
        var encryptedCorrectly = false
        var wrongWasReady = false
        listener.stateUpdateHandler = { state in if case .ready = state { listening.signal() } }
        listener.newConnectionHandler = { connection in
            let server = PeerLink(connection, callbackQueue: callbackQueue)
            accepted.append(server)
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
            using: PeerNetwork.parameters(code: code)), callbackQueue: callbackQueue)
        client.onReady = { [weak client] in
            if let metadata = client?.connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
                encryptedCorrectly = sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata.securityProtocolMetadata).rawValue
                    == UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)
            }
            client?.send(.hello, payload)
        }
        client.onPacket = { packet in receivedCorrectly = packet.kind == .ready && packet.body == payload; reply.signal() }
        client.start()
        defer { client.cancel() }
        try expect(reply.wait(timeout: .now() + 8) == .success && receivedCorrectly && encryptedCorrectly, "TLS 正确配对、加密套件或大数据包传输失败")

        let wrong = PeerLink(NWConnection(host: "127.0.0.1", port: port,
            using: PeerNetwork.parameters(code: "ZZZZ-ZZZZ-ZZZZ")), callbackQueue: callbackQueue)
        wrong.onReady = { wrongWasReady = true; wrongClosed.signal() }
        wrong.onClosed = { _ in wrongClosed.signal() }
        wrong.start()
        defer { wrong.cancel() }
        let wrongResult = wrongClosed.wait(timeout: .now() + 8)
        try expect(wrongResult == .success && !wrongWasReady, "错误配对码未被 TLS 拒绝")
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
        if CommandLine.arguments.contains("--receiver-smoke-test") { DiagnosticTests.receiverSmokeTest() }
        if CommandLine.arguments.contains("--mirror-smoke-test") { MirrorCaptureCheck.run() }
        MacPairApp.main()
    }
}
