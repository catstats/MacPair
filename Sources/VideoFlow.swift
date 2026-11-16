// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum VideoClock {
    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func microseconds(_ ns: UInt64) -> UInt32 { UInt32(min(UInt64(UInt32.max), ns / 1_000)) }
}

struct VideoPipelineOptions: Codable, Equatable {
    let version: Int
    let maximumFrames: Int
    let frameRate: Int
    init(version: Int = 1, maximumFrames: Int = 2, frameRate: Int = 60) {
        self.version = version; self.maximumFrames = maximumFrames; self.frameRate = frameRate
    }
    func validate() throws {
        guard version == 1, maximumFrames == 2, frameRate == 60 else {
            throw PairError.message("Unsupported video feedback settings")
        }
    }
}

struct VideoFrame {
    let id: UInt64
    let bytes: Data
    var data: Data { var result = Data(); result.appendBE(id); result.append(bytes); return result }
    init(id: UInt64, bytes: Data) { self.id = id; self.bytes = bytes }
    init(_ data: Data) throws {
        guard data.count > 8, data.uint64BE() > 0 else { throw PairError.message("Invalid video frame identifier") }
        id = data.uint64BE(); bytes = Data(data.dropFirst(8))
    }
}

struct VideoAcknowledgement {
    let id: UInt64
    let dispatchUS: UInt32
    let sampleUS: UInt32
    let rendererWaitUS: UInt32
    var data: Data {
        var result = Data(); result.appendBE(id)
        result.appendBE(dispatchUS); result.appendBE(sampleUS); result.appendBE(rendererWaitUS)
        return result
    }
    init(id: UInt64, dispatchUS: UInt32, sampleUS: UInt32, rendererWaitUS: UInt32) {
        self.id = id; self.dispatchUS = dispatchUS; self.sampleUS = sampleUS; self.rendererWaitUS = rendererWaitUS
    }
    init(_ data: Data) throws {
        guard data.count == 20, data.uint64BE() > 0 else { throw PairError.message("Invalid video acknowledgement") }
        id = data.uint64BE(); dispatchUS = data.uint32BE(at: 8)
        sampleUS = data.uint32BE(at: 12); rendererWaitUS = data.uint32BE(at: 16)
    }
}

/// Credits cover encoding, TCP and receiver submission together. Only raw
/// captures can be replaced; an encoded predictive frame is never discarded.
struct VideoFrameWindow {
    struct Entry { let capturedAt: UInt64; var encodedAt: UInt64? }
    let limit: Int
    private var nextID: UInt64 = 1
    private(set) var entries: [UInt64: Entry] = [:]
    init(limit: Int) { self.limit = limit }
    var count: Int { entries.count }
    var available: Bool { entries.count < limit }
    var oldest: UInt64? { entries.values.map(\.capturedAt).min() }
    mutating func reserve(capturedAt: UInt64) -> UInt64? {
        guard available, nextID < UInt64.max else { return nil }
        let id = nextID; nextID += 1
        entries[id] = Entry(capturedAt: capturedAt, encodedAt: nil); return id
    }
    mutating func encoded(_ id: UInt64, at now: UInt64) throws {
        guard entries[id] != nil else { throw PairError.message("Invalid video acknowledgement") }
        entries[id]?.encodedAt = now
    }
    mutating func retire(_ id: UInt64, ordered: Bool) throws -> Entry {
        guard let entry = entries[id], entry.encodedAt != nil,
              !ordered || entries.keys.min() == id else {
            throw PairError.message("Invalid video acknowledgement")
        }
        entries.removeValue(forKey: id); return entry
    }
}

struct VideoMetricsSnapshot {
    let counts: [String: Int]
    let totals: [String: Int]
    let times: [String: [Double]]
    let outstanding: Int
    let peakOutstanding: Int
    let intervalSeconds: Double
    func rate(_ key: String) -> Double { Double(counts[key, default: 0]) / max(0.001, intervalSeconds) }
    func mean(_ key: String) -> Double {
        let values = times[key] ?? []; return values.isEmpty ? 0 : values.reduce(0,+) / Double(values.count)
    }
    func p95(_ key: String) -> Double {
        let values = (times[key] ?? []).sorted()
        return values.isEmpty ? 0 : values[Int(Double(values.count - 1) * 0.95)]
    }
    func milliseconds(_ key: String) -> String { times[key]?.isEmpty == false ? String(format: "%.1f", mean(key)) : "—" }
    var summary: String {
        func frequency(_ key: String) -> String { String(format: "%.1f", rate(key)) }
        let percentile = times["encode"]?.isEmpty == false ? String(format: "%.1f", p95("encode")) : "—"
        let flow = "\(L("Capture")) \(frequency("capture"))/s · \(L("Encode")) \(frequency("encode"))/s · \(L("Send")) \(frequency("send"))/s · ACK \(frequency("ack"))/s"
        let timings = "\(L("Raw wait")) \(milliseconds("raw")) ms · \(L("Encode avg/p95")) \(milliseconds("encode"))/\(percentile) ms · \(L("Local send")) \(milliseconds("send")) ms"
        let feedback = "\(L("Callback → receiver submit → ACK")) \(milliseconds("ack")) ms (\(L("includes return trip")))"
        let receiver = "\(L("Receiver queue / sample / renderer wait")) \(milliseconds("dispatch"))/\(milliseconds("sample"))/\(milliseconds("renderer")) ms"
        return [flow, timings, feedback, receiver,
            "\(L("Raw frames replaced")) \(frequency("replace"))/s · \(L("Outstanding")) \(outstanding) (\(L("Peak")) \(peakOutstanding))"].joined(separator: "\n")
    }

}

final class VideoMetrics {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var totals: [String: Int] = [:]
    private var times: [String: [Double]] = [:]
    private var outstanding = 0
    private var peakOutstanding = 0
    private var intervalStart = VideoClock.now
    func event(_ key: String) { lock.withLock { counts[key, default: 0] += 1; totals[key, default: 0] += 1 } }
    func timing(_ key: String, ns: UInt64) {
        lock.withLock {
            times[key, default: []].append(Double(ns) / 1e6)
            if times[key, default: []].count > 120 { times[key]?.removeFirst() }
        }
    }
    func depth(_ value: Int) { lock.withLock { outstanding = value; peakOutstanding = max(peakOutstanding, value) } }
    func snapshot(reset: Bool = true) -> VideoMetricsSnapshot {
        lock.withLock {
            let now = VideoClock.now
            let result = VideoMetricsSnapshot(counts: counts, totals: totals, times: times, outstanding: outstanding,
                peakOutstanding: peakOutstanding, intervalSeconds: Double(now - intervalStart) / 1e9)
            if reset { counts.removeAll(keepingCapacity: true); times.removeAll(keepingCapacity: true); intervalStart = now }
            return result
        }
    }
}
