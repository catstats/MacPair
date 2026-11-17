// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreVideo
import VideoToolbox

final class Probe {
    let lock = NSLock()
    let credit: DispatchSemaphore
    let completed = DispatchSemaphore(value: 0)
    var starts: [Int: UInt64] = [:]
    var latencies: [Double] = []
    var ids: [Int] = []
    var failed: String?
    var firstSteady: UInt64?
    var last: UInt64 = 0
    init(_ slots: Int) { credit = DispatchSemaphore(value: slots) }
    func output(_ id: Int, _ status: OSStatus, _ flags: VTEncodeInfoFlags, _ sample: CMSampleBuffer?) {
        lock.lock()
        let now = DispatchTime.now().uptimeNanoseconds
        if status != noErr || flags.contains(.frameDropped) || sample == nil { failed = "encode status \(status)" }
        if let start = starts[id], id >= 10 { latencies.append(Double(now - start) / 1e6) }
        ids.append(id); last = now
        lock.unlock(); credit.signal(); completed.signal()
    }
}
func pattern(_ width: Int, _ height: Int, _ offset: Int) -> CVPixelBuffer {
    var result: CVPixelBuffer?
    precondition(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result) == kCVReturnSuccess)
    let buffer = result!; CVPixelBufferLockBaseAddress(buffer, [])
    let y = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
    let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
    let ys = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
    for row in 0..<height {
        for x in stride(from: 0, to: width, by: 16) { memset(y + row * ys + x, (x / 64 + row / 32 + offset) % 5 == 0 ? 190 : 60, min(16, width - x)) }
    }
    for row in 0..<(height / 2) { memset(uv + row * uvs, 128, width) }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    return buffer
}
func measure(_ width: Int, _ height: Int, _ slots: Int) -> [String: Any] {
    let probe = Probe(slots)
    let specification: [CFString: Any] = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true, kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true]
    let callback: VTCompressionOutputCallback = { context, frame, status, flags, sample in
        let probe = Unmanaged<Probe>.fromOpaque(context!).takeUnretainedValue()
        probe.output(Int(bitPattern: frame) - 1, status, flags, sample)
    }
    var session: VTCompressionSession?
    precondition(VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
        encoderSpecification: specification as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil,
        outputCallback: callback, refcon: Unmanaged.passUnretained(probe).toOpaque(), compressionSessionOut: &session) == noErr)
    let encoder = session!
    defer { VTCompressionSessionCompleteFrames(encoder, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(encoder) }
    let properties: [CFString: Any] = [kVTCompressionPropertyKey_RealTime: true, kVTCompressionPropertyKey_AllowFrameReordering: false,
        kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel, kVTCompressionPropertyKey_ExpectedFrameRate: 60,
        kVTCompressionPropertyKey_MaxKeyFrameInterval: 120, kVTCompressionPropertyKey_AverageBitRate: 45_000_000]
    for (key, value) in properties { precondition(VTSessionSetProperty(encoder, key: key, value: value as CFTypeRef) == noErr) }
    _ = VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as NSNumber)
    precondition(VTCompressionSessionPrepareToEncodeFrames(encoder) == noErr)
    let buffers = (0..<8).map { pattern(width, height, $0) }
    for id in 0..<100 {
        precondition(probe.credit.wait(timeout: .now() + 5) == .success)
        let now = DispatchTime.now().uptimeNanoseconds
        probe.lock.lock(); probe.starts[id] = now; if id == 10 { probe.firstSteady = now }; probe.lock.unlock()
        precondition(VTCompressionSessionEncodeFrame(encoder, imageBuffer: buffers[id % 8], presentationTimeStamp: CMTime(value: Int64(id), timescale: 60),
            duration: CMTime(value: 1, timescale: 60), frameProperties: id == 0 ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil,
            sourceFrameRefcon: UnsafeMutableRawPointer(bitPattern: id + 1), infoFlagsOut: nil) == noErr)
    }
    for _ in 0..<100 { precondition(probe.completed.wait(timeout: .now() + 5) == .success) }
    precondition(probe.failed == nil && probe.ids.count == 100 && Set(probe.ids).count == 100)
    let values = probe.latencies.sorted()
    return ["width": width, "height": height, "encoderSlots": slots, "encodeFPS": Double(values.count) * 1e9 / Double(probe.last - probe.firstSteady!),
        "encodeMeanMS": values.reduce(0,+) / Double(values.count), "encodeP95MS": values[Int(ceil(Double(values.count) * 0.95)) - 1],
        "orderedCallbacks": probe.ids == Array(0..<100), "frames": probe.ids.count]
}
var results: [[String: Any]] = []
for (width, height) in [(2940, 1846), (3676, 2308)] {
    for slots in [1, 2, 3] {
        let result = measure(width, height, slots); results.append(result)
        fputs("Measured \(width)x\(height), encoder slots \(slots): \(result)\n", stderr)
    }
}
let bytes = try! JSONSerialization.data(withJSONObject: ["scope": "Generated encoder-only probe; unpaced submissions; excludes SCK, AWDL, decode and presentation", "results": results], options: [.prettyPrinted, .sortedKeys])
print(String(decoding: bytes, as: UTF8.self))
