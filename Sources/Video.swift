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
    var onOutput: ((Data?, Data?, LocalizedMessage?) -> Void)?
    init(width: Int, height: Int, fps: Int) throws {
        self.fps = fps
        bitrate = min(45_000_000, max(8_000_000, Int(Double(width) * Double(height) * Double(fps) * 0.18)))
        var result: VTCompressionSession?
        let specification = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: specification, imageBufferAttributes: nil,
            compressedDataAllocator: nil, outputCallback: { context, _, status, flags, sample in
                guard let context else { return }
                let encoder = Unmanaged<H264Encoder>.fromOpaque(context).takeUnretainedValue()
                guard status == noErr, !flags.contains(.frameDropped), let sample else {
                    encoder.onOutput?(nil, nil, "Video encoding failed (\(status))"); return
                }
                encoder.output(sample)
            }, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &result)
        try checkStatus(status, "Create H.264 encoder")
        guard let result else { throw PairError.message("No H.264 encoder is available") }
        session = result
        do {
            let properties: [CFString: Any] = [
                kVTCompressionPropertyKey_RealTime: true,
                kVTCompressionPropertyKey_AllowFrameReordering: false,
                kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Main_AutoLevel,
                kVTCompressionPropertyKey_ExpectedFrameRate: fps,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: fps * 2,
                kVTCompressionPropertyKey_AverageBitRate: bitrate
            ]
            for (key, value) in properties {
                try checkStatus(VTSessionSetProperty(result, key: key, value: value as CFTypeRef), "Set H.264 property \(key)")
            }
            try checkStatus(VTCompressionSessionPrepareToEncodeFrames(result), "Prepare encoder")
        } catch { stop(); throw error }
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

final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    private let link: PeerLink
    private let encoder: H264Encoder
    private let queue = DispatchQueue(label: "MacPair.capture", qos: .userInteractive)
    private var stream: SCStream?
    private let lock = NSLock()
    private var busy = false
    private var stopped = false
    private var needsKeyframe = true
    private var reportedDimensions = false
    private let expectedWidth: Int
    private let expectedHeight: Int
    var onCaptureInfo: ((LocalizedMessage) -> Void)?
    var onError: ((LocalizedMessage) -> Void)?
    var onSent: (() -> Void)?

    init(link: PeerLink, width: Int, height: Int, fps: Int) throws {
        self.link = link
        self.expectedWidth = width
        self.expectedHeight = height
        self.encoder = try H264Encoder(width: width, height: height, fps: fps)
        super.init()
        encoder.onOutput = { [weak self] format, video, error in
            guard let self else { return }
            if let error { self.releaseFrame(); self.onError?(error); return }
            guard let video else { self.releaseFrame(); return }
            if let format { self.link.send(.format, format) }
            self.link.send(.video, video) { [weak self] ok in
                self?.releaseFrame()
                if ok { self?.onSent?() }
            }
        }
    }
    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int) async throws {
        var target: SCDisplay?
        for _ in 0..<30 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            target = content.displays.first { $0.displayID == displayID }
            if target != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try Task.checkCancellation()
        guard let target else { throw PairError.message("Screen capture could not find the selected display") }
        onCaptureInfo?("Capture source: \(target.width) × \(target.height); encoder: \(width) × \(height) px; bitrate \(encoder.bitrate / 1_000_000) Mbps")
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false
        let filter = SCContentFilter(display: target, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        guard !busy, !stopped else { lock.unlock(); return }
        busy = true
        let force = needsKeyframe
        needsKeyframe = false
        lock.unlock()
        let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
        guard width == expectedWidth, height == expectedHeight else {
            releaseFrame()
            onError?("Screen capture returned unexpected pixel dimensions")
            return
        }
        if !reportedDimensions {
            reportedDimensions = true
            onCaptureInfo?("Actual captured frame: \(width) × \(height) px")
        }
        // Only one capture/encode/send is in flight. Skipped captures were never
        // encoded, so H.264 prediction never references a frame we discarded.
        do { try encoder.encode(image, forceKeyframe: force) }
        catch { releaseFrame(); onError?(error.appMessage) }
    }
    private func releaseFrame() { lock.lock(); busy = false; lock.unlock() }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); let report = !stopped; lock.unlock()
        if report { onError?(error.appMessage) }
    }
    func stop() async {
        lock.withLock { stopped = true }
        if let stream { try? await stream.stopCapture() }
        stream = nil
        queue.sync { encoder.stop() }
    }
}
