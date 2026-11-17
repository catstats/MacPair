// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import AVFoundation
import Network

/// Production encrypted transport and renderer on loopback; never captures a desktop.
@MainActor
private final class FlowProbe {
    var server: PeerLink?
    var failure: String?
    var listenerReady = false
    var clientReady = false
    var serverReady = false
}

@MainActor
enum VideoFlowBenchmark {
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory); app.finishLaunching()
        Task { @MainActor in
            do {
                var records: [[String: Any]] = []
                let captures = CommandLine.arguments.contains("--capture-source")
                let quick = CommandLine.arguments.contains("--quick")
                let delayCount = captures || quick ? 1 : 3
                var delayIndex = 0
                while delayIndex < delayCount {
                    let delay = captures ? 0 : (quick ? 35 : (delayIndex == 0 ? 0 : (delayIndex == 1 ? 35 : 75)))
                    var windowIndex = 0
                    while windowIndex < 4 {
                        let frames = windowIndex == 1 ? 1 : (windowIndex == 2 ? 3 : 2)
                        guard (0...75).contains(delay), records.count < delayCount * 4 else { throw PairError.message("Invalid benchmark iteration") }
                        print("START loopback delay=\(delay) ms window=\(frames)")
                        let trial: VideoTrial
                        do { trial = try await measure(frames: frames, delayMS: delay) }
                        catch { throw PairError.message(LocalizedMessage(verbatim: "delay=\(delay), window=\(frames): \(error.localizedDescription)")) }
                        let encoded = try JSONEncoder().encode(trial)
                        var value = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
                        value["artificialACKDelayMS"] = delay
                        records.append(value)
                        print("Loopback delay=\(delay) ms window=\(frames): ACK \(String(format: "%.1f", trial.measurements.rate("ack"))) fps, ACK p95 \(String(format: "%.1f", trial.measurements.times["ack"]?.p95 ?? 0)) ms, encode p95 \(String(format: "%.1f", trial.measurements.times["encode"]?.p95 ?? 0)) ms")
                        windowIndex += 1
                    }
                    delayIndex += 1
                }
                guard records.count == delayCount * 4 else { throw PairError.message("Incomplete benchmark") }
                let result: [String: Any] = ["schema": 1, "scope": captures ? "Real ScreenCaptureKit capturing ONLY this process's generated 1280x832 pt window at 2560x1664 px, then production H.264, encrypted loopback and system renderer. Excludes AWDL and physical presentation." : "Generated 2560x1664 NV12; production H.264, encrypted loopback and AVSampleBufferDisplayLayer. Excludes ScreenCaptureKit, AWDL and physical presentation.",
                    "latencyRule": VideoExperimentReport.latencyRule, "results": records]
                let bytes = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                if let index = CommandLine.arguments.firstIndex(of: "--benchmark-output"), index + 1 < CommandLine.arguments.count {
                    try bytes.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
                } else { print(String(decoding: bytes, as: UTF8.self)) }
                exit(0)
            } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        app.run(); exit(1)
    }
    private static func measure(frames: Int, delayMS: Int) async throws -> VideoTrial {
        let width = 2560, height = 1664
        let captures = CommandLine.arguments.contains("--capture-source")
        let depthIndex = CommandLine.arguments.firstIndex(of: "--capture-depth")
        let depth = depthIndex.flatMap { $0 + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[$0 + 1]) : nil } ?? 3
        guard !captures || CGPreflightScreenCaptureAccess() else { throw PairError.message("Screen Recording permission is not available; no capture attempted") }
        var sourceWindow: VideoMotionWindow?
        if captures {
            let rect = NSRect(x: 30, y: 30, width: 1280, height: 832)
            let source = VideoMotionWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            source.isReleasedWhenClosed = false; source.contentView = VideoMotionPattern(frame: NSRect(origin: .zero, size: rect.size))
            source.orderFrontRegardless(); sourceWindow = source
        }
        defer {
            (sourceWindow?.contentView as? VideoMotionPattern)?.stop(); sourceWindow?.close()
        }
        let probe = FlowProbe()
        let host = PeerIdentity(id: UUID().uuidString, name: "Generated flow host")
        let display = PeerIdentity(id: UUID().uuidString, name: "Generated flow display")
        let code = PairingCode.generate()
        let layer = AVSampleBufferDisplayLayer(); layer.videoGravity = .resizeAspect
        let view = NativeVideoView(videoLayer: layer)
        let window = NSWindow(contentRect: NSRect(x: 70, y: 70, width: 560, height: 364), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "MacPair · Generated ACK-window comparison"
        window.contentView = view; window.orderFrontRegardless()
        let receiver = VideoReceiver(layer: layer, width: width, height: height, maximumFrames: 3)
        receiver.onError = { error in DispatchQueue.main.async { probe.failure = error.localized } }
        let listener = try NWListener(using: PeerNetwork.parameters(), on: .any)
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = PeerLink(connection, host: false, code: code, identity: display)
                probe.server = peer
                peer.onReady = { [weak peer] in
                    guard let peer else { return }
                    peer.setMediaHandler { packet in
                        guard packet.kind == .format || packet.kind == .videoFrame else { return false }
                        receiver.accept(packet); return true
                    }
                    receiver.onAcknowledgement = { [weak peer] data in
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMS)) { peer?.send(.videoAck, data) }
                    }
                    probe.serverReady = true
                }
                peer.onClosed = { error in probe.failure = error.localized }; peer.start()
            }
        }
        listener.stateUpdateHandler = { state in
            Task { @MainActor in
                if case .ready = state { probe.listenerReady = true }
                if case .failed(let error) = state { probe.failure = error.localizedDescription }
            }
        }
        listener.start(queue: .main)
        var client: PeerLink?, streamer: ScreenStreamer?
        @MainActor func wait(_ stage: String, _ predicate: @MainActor () -> Bool) async throws {
            for _ in 0..<250 {
                if let failure = probe.failure { throw PairError.message(LocalizedMessage(verbatim: failure)) }
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw PairError.message(LocalizedMessage(verbatim: "Generated flow benchmark timed out at " + stage + "; sender=" + (streamer?.snapshot(reset: false).summary ?? "not created") + "; receiver=" + receiver.snapshot(reset: false).summary))
        }
        do {
            try await wait("listener") { probe.listenerReady && listener.port != nil }
            let peer = PeerLink(NWConnection(host: "127.0.0.1", port: listener.port!, using: PeerNetwork.parameters()), host: true,
                code: code, identity: host, expectedPeer: display)
            client = peer; peer.onReady = { probe.clientReady = true }
            peer.onClosed = { error in probe.failure = error.localized }; peer.start()
            try await wait("authentication") { probe.clientReady && probe.serverReady }
            let sender = try ScreenStreamer(link: peer, width: width, height: height, fps: 60,
                feedback: true, maximumFrames: 3, initialFrames: frames, captureQueueDepth: depth)
            streamer = sender
            sender.onError = { error in DispatchQueue.main.async { probe.failure = error.localized } }
            peer.setMediaHandler { [weak sender] packet in
                guard let sender, packet.kind == .videoAck else { return false }; sender.acknowledge(packet.body); return true
            }
            if let sourceWindow {
                try await sender.start(displayID: CGMainDisplayID(), width: width, height: height, fps: 60, windowID: CGWindowID(sourceWindow.windowNumber))
            }
            let buffers = try (0..<(captures ? 0 : 8)).map { try VideoBenchmark.pattern(width: width, height: height, nv12: true, offset: $0) }
            let quick = CommandLine.arguments.contains("--quick")
            let warmup = 60, count = quick ? 180 : 360
            let start = VideoClock.now
            var recording = false
            for index in 0..<(warmup + count) {
                if let failure = probe.failure { throw PairError.message(LocalizedMessage(verbatim: failure)) }
                let scheduled = start + UInt64(index) * 1_000_000_000 / 60
                let now = VideoClock.now
                if scheduled > now { try await Task.sleep(nanoseconds: scheduled - now) }
                if index == warmup { sender.beginRecording(); recording = true }
                if !captures { sender.submit(buffers[index % buffers.count]) }
            }
            let end = start + UInt64(warmup + count) * 1_000_000_000 / 60
            if VideoClock.now < end { try await Task.sleep(nanoseconds: end - VideoClock.now) }
            let measurements = sender.finishRecording()
            guard recording else { throw PairError.message("Generated flow benchmark did not record") }
            try await wait("drain") { sender.snapshot(reset: false).outstanding == 0 }
            try await Task.sleep(for: .milliseconds(100))
            let sent = sender.snapshot(reset: false), received = receiver.snapshot(reset: false)
            guard sent.peakOutstanding <= frames, received.peakOutstanding <= frames,
                  sent.totals["encode"] == sent.totals["send"], sent.totals["send"] == sent.totals["ack"],
                  sent.totals["ack"] == received.totals["submit"], layer.status != .failed else {
                throw PairError.message("Generated-video flow lost a predictive frame or exceeded its frame window")
            }
            peer.onClosed = nil; peer.onReady = nil; peer.setMediaHandler(nil)
            probe.server?.onClosed = nil; probe.server?.onReady = nil; probe.server?.setMediaHandler(nil)
            await sender.stop(); receiver.stop(); peer.cancel(); probe.server?.cancel(); listener.cancel(); window.close()
            return VideoTrial(frames: frames, queueDepth: depth, measurements: measurements)
        } catch {
            if let streamer { await streamer.stop() }
            receiver.stop(); client?.onClosed = nil; probe.server?.onClosed = nil
            client?.cancel(); probe.server?.cancel(); listener.cancel(); window.close(); throw error
        }
    }
}
