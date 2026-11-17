// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AVFoundation
import VideoToolbox
import ScreenCaptureKit

private func checkStatus(_ status: OSStatus, _ operation: LocalizedMessage) throws {
    if status != noErr { throw PairError.message("\(operation) failed (\(status))") }
}

final class H264Encoder {
    private var session: VTCompressionSession?
    private var sequence: Int64 = 0
    let fps: Int
    let bitrate: Int
    private(set) var lowLatencyEnabled = false
    var onOutput: ((Data?, Data?, LocalizedMessage?) -> Void)?
    init(width: Int, height: Int, fps: Int, lowLatency: Bool = true) throws {
        self.fps = fps
        bitrate = min(45_000_000, max(8_000_000, Int(Double(width) * Double(height) * Double(fps) * 0.18)))
        var result: VTCompressionSession?
        let callback: VTCompressionOutputCallback = { context, _, status, flags, sample in
            guard let context else { return }
            let encoder = Unmanaged<H264Encoder>.fromOpaque(context).takeUnretainedValue()
            guard status == noErr, !flags.contains(.frameDropped), let sample else {
                encoder.onOutput?(nil, nil, "Video encoding failed (\(status))"); return
            }
            encoder.output(sample)
        }
        func create(_ fast: Bool) -> OSStatus {
            var specification: [CFString: Any] = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true]
            if fast {
                specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = true
                specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true
            }
            return VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
                encoderSpecification: specification as CFDictionary, imageBufferAttributes: nil,
                compressedDataAllocator: nil, outputCallback: callback,
                refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &result)
        }
        var status = create(lowLatency)
        var selectedFast = lowLatency && status == noErr
        if status != noErr && lowLatency { result = nil; status = create(false); selectedFast = false }
        lowLatencyEnabled = selectedFast
        try checkStatus(status, "Create H.264 encoder")
        guard let result else { throw PairError.message("No H.264 encoder is available") }
        session = result
        do {
            let properties: [CFString: Any] = [
                kVTCompressionPropertyKey_RealTime: true,
                kVTCompressionPropertyKey_AllowFrameReordering: false,
                kVTCompressionPropertyKey_ProfileLevel: lowLatencyEnabled ? kVTProfileLevel_H264_High_AutoLevel : kVTProfileLevel_H264_Main_AutoLevel,
                kVTCompressionPropertyKey_ExpectedFrameRate: fps,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: fps * 2,
                kVTCompressionPropertyKey_AverageBitRate: bitrate
            ]
            for (key, value) in properties {
                try checkStatus(VTSessionSetProperty(result, key: key, value: value as CFTypeRef), "Set H.264 property \(key)")
            }
            if lowLatencyEnabled { _ = VTSessionSetProperty(result, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as NSNumber) }
            try checkStatus(VTCompressionSessionPrepareToEncodeFrames(result), "Prepare encoder")
        } catch { stop(); throw error }
    }
    func copiedProperty(_ key: CFString) -> (OSStatus, AnyObject?) {
        guard let session else { return (-1, nil) }
        var value: Unmanaged<CFTypeRef>?
        let status = VTSessionCopyProperty(session, key: key, allocator: kCFAllocatorDefault, valueOut: &value)
        return (status, value?.takeRetainedValue())
    }
    var reportedHardwareAcceleration: Bool? {
        let (status, value) = copiedProperty(kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder)
        guard status == noErr else { return nil }
        return (value as? NSNumber)?.boolValue
    }
    var encoderDetails: String {
        let (status, value) = copiedProperty(kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder)
        let identifier = copiedProperty(kVTCompressionPropertyKey_EncoderID).1 as? String ?? "unreported"
        return "encoder=\(identifier), hardware-query=\(status), value=\(value.map { String(describing: $0) } ?? "nil")"
    }
    func encode(_ pixelBuffer: CVPixelBuffer, forceKeyframe: Bool = false) throws {
        guard let session else { throw PairError.message("The encoder has stopped") }
        let properties = forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let time = CMTime(value: sequence, timescale: Int32(fps))
        sequence += 1
        try checkStatus(VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer,
            presentationTimeStamp: time, duration: CMTime(value: 1, timescale: Int32(fps)),
            frameProperties: properties, sourceFrameRefcon: nil, infoFlagsOut: nil), "Encode frame")
    }
    private func output(_ sample: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sample), let block = CMSampleBufferGetDataBuffer(sample) else {
            onOutput?(nil, nil, "Encoded output is not readable"); return
        }
        var configuration: Data?
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let keyframe = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true
        if keyframe, let format = CMSampleBufferGetFormatDescription(sample) {
            var config = Data()
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                    parameterSetIndex: index, parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                guard status == noErr, let pointer, size > 0 else {
                    onOutput?(nil, nil, "Cannot read H.264 configuration"); return
                }
                config.appendBE(UInt32(size))
                config.append(pointer, count: size)
            }
            configuration = config
        }
        var bytes = Data(count: CMBlockBufferGetDataLength(block))
        let status = bytes.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        }
        guard status == noErr else { onOutput?(nil, nil, "Cannot read video frame"); return }
        onOutput?(configuration, bytes, nil)
    }
    func stop() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }
    deinit { stop() }
}

/// The same compressed-sample builder is used by the viewer and real decoder tests.
final class H264Samples {
    private(set) var format: CMVideoFormatDescription?
    func reset() { format = nil }
    func configure(_ data: Data, expectedWidth: Int? = nil, expectedHeight: Int? = nil) throws {
        guard data.count >= 10 else { throw PairError.message("Incomplete H.264 configuration") }
        let spsSize = Int(data.uint32BE(at: 0))
        guard spsSize > 0, spsSize <= 65_536, data.count >= spsSize + 8 else {
            throw PairError.message("Invalid H.264 SPS length")
        }
        let ppsSize = Int(data.uint32BE(at: spsSize + 4))
        guard ppsSize > 0, ppsSize <= 65_536, data.count == spsSize + ppsSize + 8 else {
            throw PairError.message("Invalid H.264 PPS length")
        }
        let sps = Data(data[4..<(spsSize + 4)])
        let pps = Data(data[(spsSize + 8)...])
        var description: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { s in
            pps.withUnsafeBytes { p in
                let pointers = [s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                    parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            }
        }
        try checkStatus(status, "Parse video configuration")
        if let description, let expectedWidth, let expectedHeight {
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            guard Int(dimensions.width) == expectedWidth, Int(dimensions.height) == expectedHeight else {
                throw PairError.message("The video dimensions do not match the negotiated display")
            }
        }
        format = description
    }
    func sample(_ bytes: Data) throws -> CMSampleBuffer {
        guard let format, !bytes.isEmpty else { throw PairError.message("Video format is not ready") }
        // Validate AVCC NAL boundaries before handing network data to the decoder.
        var offset = 0
        while offset < bytes.count {
            guard bytes.count - offset >= 4 else { throw PairError.message("Incomplete video frame header") }
            let count = Int(bytes.uint32BE(at: offset))
            guard count > 0, count <= bytes.count - offset - 4 else {
                throw PairError.message("Invalid video frame length")
            }
            offset += count + 4
        }
        var block: CMBlockBuffer?
        try checkStatus(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: bytes.count, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0,
            blockBufferOut: &block), "Allocate video buffer")
        guard let block else { throw PairError.message("Cannot allocate video buffer") }
        try bytes.withUnsafeBytes {
            try checkStatus(CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                offsetIntoDestination: 0, dataLength: bytes.count), "Copy video data")
        }
        var sample: CMSampleBuffer?
        var size = bytes.count
        try checkStatus(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample), "Create video sample")
        guard let sample else { throw PairError.message("Cannot create video sample") }
        if let array = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            array.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }
}

// Encoder/window state belongs to queue; raw admission/stopping uses lock.
// Callbacks are configured before capture starts and remain immutable until stop.
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private struct Capture { let image: CVPixelBuffer; let at: UInt64; let sourceAt: UInt64? }
    private struct Encoding { let id: UInt64; let started: UInt64 }
    private let link: PeerLink
    private let encoder: H264Encoder
    private let queue = DispatchQueue(label: "MacPair.encode", qos: .userInteractive)
    private let captureQueue = DispatchQueue(label: "MacPair.capture", qos: .userInteractive)
    private let lock = NSLock()
    private var latest: Capture?
    private var pumpScheduled = false
    private var stopped = false
    private var encoding: Encoding?
    private var window: VideoFrameWindow
    private let feedback: Bool
    private let maximumFrames: Int
    private var captureDepth = 3
    private var previousCapture: UInt64?
    private var previousAcknowledgement: UInt64?
    private let metrics = VideoMetrics()
    private var watchdog: DispatchSourceTimer?
    private var stream: SCStream?
    private var reportedDimensions = false
    private let expectedWidth: Int
    private let expectedHeight: Int
    var onCaptureInfo: ((LocalizedMessage) -> Void)?
    var onError: ((LocalizedMessage) -> Void)?
    var onSent: (() -> Void)?

    init(link: PeerLink, width: Int, height: Int, fps: Int, feedback: Bool = false, maximumFrames: Int = 2, initialFrames: Int = 2, captureQueueDepth: Int = 3) throws {
        guard (1...3).contains(maximumFrames), (1...maximumFrames).contains(initialFrames), (3...8).contains(captureQueueDepth) else {
            throw PairError.message("Unsupported video feedback settings")
        }
        self.link = link; self.feedback = feedback; self.maximumFrames = maximumFrames; self.captureDepth = captureQueueDepth
        self.window = VideoFrameWindow(limit: feedback ? initialFrames : 1)
        expectedWidth = width; expectedHeight = height
        encoder = try H264Encoder(width: width, height: height, fps: fps)
        super.init()
        encoder.onOutput = { [weak self] format, video, error in
            guard let self else { return }
            self.queue.async { self.encoded(format: format, video: video, error: error) }
        }
    }
    var encoderInfo: String {
        "H.264 \(encoder.encoderDetails)\n\(L("Hardware required"))=\(encoder.lowLatencyEnabled) · \(L("Low latency"))=\(encoder.lowLatencyEnabled) · NV12/420v · \(L("Frame feedback"))=\(feedback)"
    }
    func snapshot(reset: Bool = true) -> VideoMetricsSnapshot { metrics.snapshot(reset: reset) }

    func setFrameLimit(_ limit: Int) async throws {
        guard feedback, (1...maximumFrames).contains(limit) else { throw PairError.message("Unsupported video feedback settings") }
        await withCheckedContinuation { continuation in
            queue.async { self.window.setLimit(limit); self.schedulePump(); continuation.resume() }
        }
    }
    func beginRecording() { metrics.beginRecording() }
    func finishRecording() -> VideoTrialMeasurements { metrics.finishRecording() }

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, windowID: CGWindowID? = nil) async throws {
        var target: SCDisplay?
        var targetWindow: SCWindow?
        for _ in 0..<30 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            target = content.displays.first { $0.displayID == displayID }
            if let windowID { targetWindow = content.windows.first { $0.windowID == windowID } }
            if target != nil, windowID == nil || targetWindow != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try Task.checkCancellation()
        guard let target else { throw PairError.message("Screen capture could not find the selected display") }
        onCaptureInfo?("Capture source: \(target.width) × \(target.height); encoder: \(width) × \(height) px; bitrate \(encoder.bitrate / 1_000_000) Mbps")
        onCaptureInfo?(LocalizedMessage(verbatim: encoderInfo))
        let configuration = SCStreamConfiguration()
        configuration.width = width; configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        configuration.queueDepth = captureDepth
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorMatrix = kCVImageBufferYCbCrMatrix_ITU_R_709_2
        configuration.showsCursor = true; configuration.capturesAudio = false
        let filter: SCContentFilter
        if let windowID {
            guard let targetWindow, targetWindow.windowID == windowID else { throw PairError.message("Generated capture window was not found") }
            filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        } else { filter = SCContentFilter(display: target, excludingApplications: [], exceptingWindows: []) }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        self.stream = stream
        queue.async { self.startWatchdog() }
        try await stream.startCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ticks = attachments.first?[.displayTime] as? UInt64
        submit(image, sourceAt: ticks.map { VideoClock.nanoseconds(ticks: $0) })
    }

    /// The production capture callback and generated-frame tests share admission.
    /// Only this one latest raw buffer may wait; encoded frames stay ordered.
    func submit(_ image: CVPixelBuffer, sourceAt: UInt64? = nil) {
        guard CVPixelBufferGetWidth(image) == expectedWidth, CVPixelBufferGetHeight(image) == expectedHeight else {
            onError?("Screen capture returned unexpected pixel dimensions"); return
        }
        let at = VideoClock.now
        metrics.event("capture")
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        let replaced = latest != nil
        let validSource = sourceAt.flatMap { $0 <= at && at - $0 < 5_000_000_000 ? $0 : nil }
        latest = Capture(image: image, at: at, sourceAt: validSource)
        if let previousCapture { metrics.timing("captureInterval", ns: at - previousCapture) }
        previousCapture = at
        if let validSource { metrics.timing("captureAge", ns: at - validSource) }
        lock.unlock()
        if replaced { metrics.event("replace") }
        schedulePump()
    }

    private func schedulePump() {
        lock.lock()
        let schedule = !stopped && !pumpScheduled && latest != nil
        if schedule { pumpScheduled = true }
        lock.unlock()
        if schedule { queue.async { [weak self] in self?.pump() } }
    }
    private func pump() {
        lock.lock(); pumpScheduled = false
        guard !stopped, encoding == nil, let capture = latest else { lock.unlock(); return }
        guard window.available else {
            metrics.setCreditBlocked(true)
            lock.unlock(); return
        }
        metrics.setCreditBlocked(false)
        latest = nil
        lock.unlock()
        guard let id = window.reserve(capturedAt: capture.at, sourceAt: capture.sourceAt) else { return }
        let now = VideoClock.now
        metrics.depth(window.count); metrics.timing("raw", ns: now - capture.at)
        encoding = Encoding(id: id, started: now)
        if !reportedDimensions {
            reportedDimensions = true
            onCaptureInfo?("Actual captured frame: \(expectedWidth) × \(expectedHeight) px")
        }
        do { try encoder.encode(capture.image, forceKeyframe: id == 1) }
        catch { onError?(error.appMessage) }
    }
    private func encoded(format: Data?, video: Data?, error: LocalizedMessage?) {
        guard !lock.withLock({ stopped }) else { return }
        guard let current = encoding else { onError?("Unexpected encoded frame"); return }
        encoding = nil
        if let error { onError?(error); return }
        guard let video else { onError?("Encoded output is not readable"); return }
        guard video.count + (feedback ? 8 : 0) + PacketCipher.overhead + 1 <= Wire.maximumPacket else {
            onError?("Encoded video frame exceeds the packet limit. Choose Larger Text and reconnect."); return
        }
        let now = VideoClock.now
        do { try window.encoded(current.id, at: now) }
        catch { onError?(error.appMessage); return }
        metrics.event("bytes", count: video.count)
        metrics.event("encode"); metrics.timing("encode", ns: now - current.started)
        if let format { link.send(.format, format) }
        let payload = feedback ? VideoFrame(id: current.id, bytes: video).data : video
        link.send(feedback ? .videoFrame : .video, payload, timing: { [weak self] queued, encrypt, local in
            self?.metrics.timing("sendQueue", ns: queued)
            self?.metrics.timing("encrypt", ns: encrypt)
            self?.metrics.timing("localTransport", ns: local)
        }) { [weak self] ok in
            guard let self else { return }
            self.queue.async {
                guard !self.lock.withLock({ self.stopped }) else { return }
                if ok {
                    self.metrics.event("send"); self.metrics.timing("send", ns: VideoClock.now - now)
                    self.onSent?()
                    if !self.feedback {
                        do { _ = try self.window.retire(current.id, ordered: false) }
                        catch { self.onError?(error.appMessage) }
                        self.metrics.depth(self.window.count)
                        self.schedulePump()
                    }
                } else { self.onError?("Video send failed") }
            }
        }
        schedulePump()
    }
    func acknowledge(_ data: Data) {
        queue.async { [weak self] in
            guard let self, self.feedback, !self.lock.withLock({ self.stopped }) else { return }
            do {
                guard data.count == (self.maximumFrames == 3 ? 24 : 20) else { throw PairError.message("Invalid video acknowledgement") }
                let acknowledgement = try VideoAcknowledgement(data)
                let entry = try self.window.retire(acknowledgement.id, ordered: true)
                let acknowledgedAt = VideoClock.now
                if let previous = self.previousAcknowledgement { self.metrics.timing("ackInterval", ns: acknowledgedAt - previous) }
                self.previousAcknowledgement = acknowledgedAt
                self.metrics.event("ack")
                self.metrics.timing("ack", ns: VideoClock.now - entry.capturedAt)
                if let sourceAt = entry.sourceAt { self.metrics.timing("sourceAck", ns: VideoClock.now - sourceAt) }
                if let encodedAt = entry.encodedAt { self.metrics.timing("afterEncodeAck", ns: VideoClock.now - encodedAt) }
                if let decrypt = acknowledgement.decryptUS { self.metrics.timing("decrypt", ns: UInt64(decrypt) * 1_000) }
                self.metrics.timing("dispatch", ns: UInt64(acknowledgement.dispatchUS) * 1_000)
                self.metrics.timing("sample", ns: UInt64(acknowledgement.sampleUS) * 1_000)
                self.metrics.timing("renderer", ns: UInt64(acknowledgement.rendererWaitUS) * 1_000)
                self.metrics.depth(self.window.count)
                self.schedulePump()
            } catch { self.onError?(error.appMessage) }
        }
    }
    private func startWatchdog() {
        guard feedback, !lock.withLock({ stopped }) else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, let oldest = self.window.oldest else { return }
            if VideoClock.now - oldest > 3_000_000_000 {
                self.onError?("The video receiver stopped accepting frames. Reconnect to resume.")
            }
        }
        watchdog = timer; timer.resume()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if !lock.withLock({ stopped }) { onError?(error.appMessage) }
    }
    func stop() async {
        lock.withLock { stopped = true; latest = nil }
        if let stream { try? await stream.stopCapture() }
        stream = nil
        await withCheckedContinuation { continuation in
            queue.async {
                self.watchdog?.cancel(); self.watchdog = nil
                self.encoder.stop()
                continuation.resume()
            }
        }
    }
}
