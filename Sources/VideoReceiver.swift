// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AVFoundation

/// Parses compressed samples off the UI thread. At most the negotiated number of frames
/// may be waiting/being submitted. Never drops an encoded P-frame.
// Parsing is queue-confined, presentation is MainActor-confined, and stopping
// and metric access are locked. Configure callbacks before installing the handler.
final class VideoReceiver: @unchecked Sendable {
    private struct Delivery {
        let id: UInt64
        let sample: CMSampleBuffer
        let receivedAt: UInt64
        let builtAt: UInt64
        let dispatchUS: UInt32
        let sampleUS: UInt32
        let decryptUS: UInt32
    }
    private let queue = DispatchQueue(label: "MacPair.video-receive", qos: .userInteractive)
    private let lock = NSLock()
    private var stopped = false
    private let samples = H264Samples()
    private let width: Int
    private let height: Int
    private let maximumFrames: Int
    private var expectedID: UInt64 = 1
    private var pending = 0
    private let metrics = VideoMetrics()
    private let layer: AVSampleBufferDisplayLayer
    @MainActor private var deliveries: [Delivery] = []
    @MainActor private var polling = false
    var onAcknowledgement: ((Data) -> Void)?
    var onError: ((LocalizedMessage) -> Void)?
    var onDimensions: ((Int, Int) -> Void)?
    var onSubmitted: (() -> Void)?

    @MainActor
    init(layer: AVSampleBufferDisplayLayer, width: Int, height: Int, maximumFrames: Int = 2) {
        self.layer = layer; self.width = width; self.height = height; self.maximumFrames = maximumFrames
    }
    func snapshot(reset: Bool = true) -> VideoMetricsSnapshot { metrics.snapshot(reset: reset) }
    func accept(_ packet: Packet) {
        queue.async { [weak self] in
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            do {
                if packet.kind == .format {
                    try self.samples.configure(packet.body, expectedWidth: self.width, expectedHeight: self.height)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.lock.withLock({ self.stopped }) else { return }
                        self.onDimensions?(self.width, self.height)
                    }
                } else {
                    guard packet.kind == .videoFrame, self.pending < self.maximumFrames else {
                        throw PairError.message("Video receiver exceeded the negotiated frame window")
                    }
                    let start = VideoClock.now
                    let frame = try VideoFrame(packet.body)
                    guard frame.id == self.expectedID, self.expectedID < UInt64.max else {
                        throw PairError.message("Invalid video frame identifier")
                    }
                    self.expectedID += 1
                    let sample = try self.samples.sample(frame.bytes)
                    let built = VideoClock.now
                    self.pending += 1; self.metrics.depth(self.pending)
                    let delivery = Delivery(id: frame.id, sample: sample, receivedAt: packet.receivedAt,
                        builtAt: built, dispatchUS: VideoClock.microseconds(start - packet.receivedAt),
                        sampleUS: VideoClock.microseconds(built - start), decryptUS: VideoClock.microseconds(packet.decryptNS))
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.lock.withLock({ self.stopped }) else { return }
                        self.deliveries.append(delivery)
                        self.drain()
                    }
                }
            } catch { self.fail(error.appMessage) }
        }
    }
    @MainActor
    private func drain() {
        guard !lock.withLock({ stopped }) else { deliveries.removeAll(); return }
        if layer.status == .failed {
            fail("Video display failed: \(layer.error?.localizedDescription ?? "unknown error")"); return
        }
        while !deliveries.isEmpty, layer.isReadyForMoreMediaData {
            let frame = deliveries.removeFirst()
            layer.enqueue(frame.sample)
            let now = VideoClock.now
            metrics.event("submit")
            metrics.timing("dispatch", ns: UInt64(frame.dispatchUS) * 1_000)
            metrics.timing("sample", ns: UInt64(frame.sampleUS) * 1_000)
            metrics.timing("renderer", ns: now - frame.builtAt)
            queue.async { [weak self] in
                guard let self else { return }
                self.pending -= 1; self.metrics.depth(self.pending)
            }
            onSubmitted?()
            onAcknowledgement?(VideoAcknowledgement(id: frame.id, dispatchUS: frame.dispatchUS,
                sampleUS: frame.sampleUS, rendererWaitUS: VideoClock.microseconds(now - frame.builtAt),
                decryptUS: maximumFrames == 3 ? frame.decryptUS : nil).data)
        }
        if let first = deliveries.first {
            if VideoClock.now - first.receivedAt > 2_000_000_000 {
                fail("The video renderer stopped accepting frames. Reconnect to resume."); return
            }
            if !polling {
                polling = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.003) { [weak self] in
                    self?.polling = false; self?.drain()
                }
            }
        }
    }
    @MainActor
    func loadRendererStatistics(_ completion: @escaping (VideoRendererStatistics?) -> Void) {
        guard !lock.withLock({ stopped }) else { completion(nil); return }
        if #available(macOS 14.4, *) {
            layer.sampleBufferRenderer.loadVideoPerformanceMetrics { value in
                guard let value else { completion(nil); return }
                let stats = VideoRendererStatistics(at: VideoClock.now, total: value.totalNumberOfFrames,
                    dropped: value.numberOfDroppedFrames, corrupted: value.numberOfCorruptedFrames,
                    accumulatedDelayMS: value.totalAccumulatedFrameDelay * 1000)
                do { try stats.validate(); completion(stats) } catch { completion(nil) }
            }
        } else { completion(nil) }
    }
    private func fail(_ reason: LocalizedMessage) {
        let first = lock.withLock { () -> Bool in
            guard !stopped else { return false }; stopped = true; return true
        }
        if first { onError?(reason) }
    }
    @MainActor
    func stop() {
        lock.withLock { stopped = true }
        deliveries.removeAll()
        queue.async { [weak self] in self?.samples.reset() }
    }
}
