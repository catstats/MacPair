// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreVideo
import VideoToolbox

private final class BenchmarkDecoder {
    let done = DispatchSemaphore(value: 0)
    var status: OSStatus = noErr
    var decodedWidth = 0
}

/// Generated moving-window patterns only. No screen capture or user pixels.
enum VideoBenchmark {
    static func run() -> Never {
        setbuf(stdout, nil)
        do {
            var records: [[String: Any]] = []
            for (width, height) in [(1230, 800), (2560, 1664)] {
                for nv12 in [false, true] {
                    records.append(try codec(width: width, height: height, nv12: nv12))
                }
            }
            let result: [String: Any] = ["scope": "synthetic codec only; excludes screen capture, AWDL and presentation",
                "framesPerCase": 90, "results": records]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        } catch {
            fputs("Performance check failed: " + error.localizedDescription + "\n", stderr)
            exit(1)
        }
    }
    private static func check(_ ok: Bool, _ message: String) throws {
        if !ok { throw PairError.message(LocalizedMessage(stringLiteral: message)) }
    }
    static func pattern(width: Int, height: Int, nv12: Bool, offset: Int) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let pixelFormat = nv12 ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : kCVPixelFormatType_32BGRA
        try check(CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result) == kCVReturnSuccess, "Cannot create synthetic frame")
        guard let result else { throw PairError.message("Cannot create synthetic frame") }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        if nv12 {
            let yBase = CVPixelBufferGetBaseAddressOfPlane(result, 0)!.assumingMemoryBound(to: UInt8.self)
            let uvBase = CVPixelBufferGetBaseAddressOfPlane(result, 1)!.assumingMemoryBound(to: UInt8.self)
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(result, 0)
            let uvStride = CVPixelBufferGetBytesPerRowOfPlane(result, 1)
            for y in 0..<height {
                for x in stride(from: 0, to: width, by: 16) {
                    let light = ((x / 64 + y / 32 + offset) % 5) == 0
                    memset(yBase + y * yStride + x, light ? 190 : 60, min(16, width - x))
                }
            }
            for y in 0..<(height / 2) { memset(uvBase + y * uvStride, 128, width) }
            CVBufferSetAttachment(result, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        } else {
            let base = CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt32.self)
            let row = CVPixelBufferGetBytesPerRow(result) / 4
            for y in 0..<height {
                for x in stride(from: 0, to: width, by: 16) {
                    let color: UInt32 = ((x / 64 + y / 32 + offset) % 5) == 0 ? 0xffbcbcbc : 0xff333333
                    (base + y * row + x).initialize(repeating: color, count: min(16, width - x))
                }
            }
        }
        return result
    }
    private static func codec(width: Int, height: Int, nv12: Bool) throws -> [String: Any] {
        let encoder = try H264Encoder(width: width, height: height, fps: 60, lowLatency: !CommandLine.arguments.contains("--legacy-encoder"))
        defer { encoder.stop() }
        let buffers = try (0..<2).map { try pattern(width: width, height: height, nv12: nv12, offset: $0) }
        let encoded = DispatchSemaphore(value: 0)
        var config: Data?, video: Data?, encodeError: LocalizedMessage?
        encoder.onOutput = { configuration, data, error in
            config = configuration; video = data; encodeError = error; encoded.signal()
        }
        let samples = H264Samples()
        let probe = BenchmarkDecoder()
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { context, _, status, _, image, _, _ in
            guard let context else { return }
            let probe = Unmanaged<BenchmarkDecoder>.fromOpaque(context).takeUnretainedValue()
            probe.status = status
            if let image { probe.decodedWidth = CVPixelBufferGetWidth(image) }
            probe.done.signal()
        }, decompressionOutputRefCon: Unmanaged.passUnretained(probe).toOpaque())
        var decoder: VTDecompressionSession?
        defer { if let decoder { VTDecompressionSessionInvalidate(decoder) } }
        var encodeMS: [Double] = [], buildMS: [Double] = [], decodeMS: [Double] = []
        var byteCount = 0
        for index in 0..<90 {
            let start = DispatchTime.now().uptimeNanoseconds
            try encoder.encode(buffers[index % buffers.count], forceKeyframe: index == 0)
            try check(encoded.wait(timeout: .now() + 5) == .success, "Encoding timed out")
            if let encodeError { throw PairError.message(encodeError) }
            let afterEncode = DispatchTime.now().uptimeNanoseconds
            if let config { try samples.configure(config, expectedWidth: width, expectedHeight: height) }
            guard let video else { throw PairError.message("No H.264 output") }
            let sample = try samples.sample(video)
            let afterBuild = DispatchTime.now().uptimeNanoseconds
            if decoder == nil {
                try check(VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: samples.format!,
                    decoderSpecification: [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true] as CFDictionary,
                    imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] as CFDictionary,
                    outputCallback: &callback, decompressionSessionOut: &decoder) == noErr, "Decoder setup failed")
            }
            try check(VTDecompressionSessionDecodeFrame(decoder!, sampleBuffer: sample, flags: [._EnableAsynchronousDecompression],
                frameRefcon: nil, infoFlagsOut: nil) == noErr, "Decoding failed")
            try check(probe.done.wait(timeout: .now() + 5) == .success && probe.status == noErr && probe.decodedWidth == width,
                "Decoder output failed")
            let afterDecode = DispatchTime.now().uptimeNanoseconds
            if index >= 5 {
                encodeMS.append(Double(afterEncode - start) / 1e6)
                buildMS.append(Double(afterBuild - afterEncode) / 1e6)
                decodeMS.append(Double(afterDecode - afterBuild) / 1e6)
                byteCount += video.count
            }
        }
        func summary(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            return ["mean": values.reduce(0,+) / Double(values.count), "p95": sorted[Int(Double(sorted.count - 1) * 0.95)]]
        }
        var hardwareDecode: Unmanaged<CFTypeRef>?
        if let decoder { VTSessionCopyProperty(decoder, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault, valueOut: &hardwareDecode) }
        return ["width": width, "height": height, "input": nv12 ? "NV12/420v" : "BGRA",
            "hardwareEncode": encoder.reportedHardwareAcceleration.map { $0 ? "yes" : "no" } ?? "unreported", "hardwareRequired": encoder.lowLatencyEnabled, "lowLatency": encoder.lowLatencyEnabled, "encoderDetails": encoder.encoderDetails, "hardwareDecode": (hardwareDecode?.takeRetainedValue() as? NSNumber)?.boolValue ?? false,
            "encodeMS": summary(encodeMS), "sampleBuildMS": summary(buildMS), "decodeMS": summary(decodeMS),
            "meanEncodedBytes": byteCount / encodeMS.count]
    }
}
