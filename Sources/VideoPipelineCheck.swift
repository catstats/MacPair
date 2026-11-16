// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import AVFoundation
import Network

/// Actual encrypted, generated moving-video path with deliberately delayed ACKs.
/// Does not create a virtual display, capture a screen, or read pairing records.
@MainActor
private final class VideoPipelineProbe {
    var server: PeerLink?
    var failure: String?
    var clientReady = false
    var serverReady = false
    var listenerReady = false
}

enum VideoPipelineCheck {
    @MainActor
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            var sender: ScreenStreamer?
            var client: PeerLink?
            let probe = VideoPipelineProbe()
            var listener: NWListener?
            var receiver: VideoReceiver?
            var window: NSWindow?
            @MainActor func wait(_ predicate: @MainActor () -> Bool, _ message: String) async throws {
                for _ in 0..<150 {
                    if let failure = probe.failure { throw PairError.message(LocalizedMessage(verbatim: failure)) }
                    if predicate() { return }
                    try await Task.sleep(for: .milliseconds(20))
                }
                throw PairError.message(LocalizedMessage(verbatim: message))
            }
            do {
                let width = 2560, height = 1664
                let host = PeerIdentity(id: UUID().uuidString, name: "Generated host")
                let display = PeerIdentity(id: UUID().uuidString, name: "Generated display")
                let code = PairingCode.generate()
                let layer = AVSampleBufferDisplayLayer()
                layer.videoGravity = .resizeAspect
                let view = NativeVideoView(videoLayer: layer)
                let generatedWindow = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 350),
                    styleMask: [.titled], backing: .buffered, defer: false)
                generatedWindow.title = "MacPair · Generated video check"
                generatedWindow.isReleasedWhenClosed = false
                generatedWindow.contentView = view
                generatedWindow.orderFrontRegardless()
                window = generatedWindow
                let videoReceiver = VideoReceiver(layer: layer, width: width, height: height)
                receiver = videoReceiver
                videoReceiver.onError = { message in DispatchQueue.main.async { probe.failure = message.localized } }
                let endpoint = try NWListener(using: PeerNetwork.parameters(), on: .any)
                listener = endpoint
                endpoint.newConnectionHandler = { connection in
                    Task { @MainActor in
                        let peer = PeerLink(connection, host: false, code: code, identity: display)
                        probe.server = peer
                        peer.onReady = {
                            probe.server?.setMediaHandler { packet in
                                guard packet.kind == .format || packet.kind == .videoFrame else { return false }
                                videoReceiver.accept(packet); return true
                            }
                            videoReceiver.onAcknowledgement = { data in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { probe.server?.send(.videoAck, data) }
                            }
                            probe.serverReady = true
                        }
                        peer.onClosed = { reason in probe.failure = reason.localized }
                        peer.start()
                    }
                }
                endpoint.stateUpdateHandler = { state in
                    Task { @MainActor in
                        if case .ready = state { probe.listenerReady = true }
                        if case .failed(let error) = state { probe.failure = error.localizedDescription }
                    }
                }
                endpoint.start(queue: .main)
                try await wait({ probe.listenerReady && endpoint.port != nil }, "Generated-video listener did not start")
                let peer = PeerLink(NWConnection(host: "127.0.0.1", port: endpoint.port!, using: PeerNetwork.parameters()),
                    host: true, code: code, identity: host, expectedPeer: display)
                client = peer
                peer.onReady = { probe.clientReady = true }
                peer.onClosed = { reason in probe.failure = reason.localized }
                peer.start()
                try await wait({ probe.clientReady && probe.serverReady }, "Generated-video authentication failed")
                let streamer = try ScreenStreamer(link: peer, width: width, height: height, fps: 60, feedback: true)
                sender = streamer
                streamer.onError = { message in DispatchQueue.main.async { probe.failure = message.localized } }
                peer.setMediaHandler { packet in
                    guard packet.kind == .videoAck else { return false }
                    streamer.acknowledge(packet.body); return true
                }
                let buffers = try (0..<2).map { try VideoBenchmark.pattern(width: width, height: height, nv12: true, offset: $0) }
                for index in 0..<90 {
                    if let failure = probe.failure { throw PairError.message(LocalizedMessage(verbatim: failure)) }
                    streamer.submit(buffers[index % buffers.count])
                    try await Task.sleep(for: .milliseconds(16))
                }
                try await wait({
                    let snapshot = streamer.snapshot(reset: false)
                    return snapshot.outstanding == 0 && snapshot.totals["ack", default: 0] > 10
                }, "Generated-video flow did not drain")
                try await Task.sleep(for: .milliseconds(100))
                let sent = streamer.snapshot(reset: false)
                let received = videoReceiver.snapshot(reset: false)
                var hasPicture = true
                if #available(macOS 14.4, *) { hasPicture = layer.isReadyForDisplay }
                guard hasPicture, sent.peakOutstanding <= 2, received.peakOutstanding <= 2,
                      sent.totals["replace", default: 0] > 0,
                      sent.totals["encode"] == sent.totals["send"],
                      sent.totals["send"] == sent.totals["ack"],
                      sent.totals["ack"] == received.totals["submit"],
                      layer.status != .failed else {
                    throw PairError.message("Generated-video flow lost a predictive frame or exceeded its frame window")
                }
                print("PASS: real encrypted Retina video, predictive-frame order, raw-frame replacement, delayed ACK backpressure and system-renderer submission")
                print("Generated/throttled check: \(sent.totals["capture", default: 0]) captures, \(sent.totals["ack", default: 0]) submitted/ACKed, peak \(sent.peakOutstanding) in flight; NOT an AWDL performance measurement")
                peer.onClosed = nil; probe.server?.onClosed = nil
                await streamer.stop()
                videoReceiver.stop(); peer.cancel(); probe.server?.cancel(); endpoint.cancel()
                generatedWindow.close()
                exit(0)
            } catch {
                if let sender { await sender.stop() }
                receiver?.stop(); client?.onClosed = nil; probe.server?.onClosed = nil
                client?.cancel(); probe.server?.cancel(); listener?.cancel(); window?.close()
                fputs("FAIL: " + error.localizedDescription + "\n", stderr)
                exit(1)
            }
        }
        app.run()
        exit(1)
    }
}
