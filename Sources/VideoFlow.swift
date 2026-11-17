// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

enum VideoClock {
    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }
    private static let timebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t(); mach_timebase_info(&value); return value
    }()
    /// WindowServer displayTime and DispatchTime use the same Mach uptime clock.
    static func nanoseconds(ticks: UInt64) -> UInt64 {
        UInt64(Double(ticks) * Double(timebase.numer) / Double(timebase.denom))
    }
    static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        end >= start ? Double(end - start) / 1e6 : -Double(start - end) / 1e6
    }
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

/// Optional extension: old peers ignore it and keep the original two-frame path.
/// Default remains two; only an explicit diagnostics experiment may use three.
struct VideoExperimentCapability: Codable, Equatable {
    let version: Int
    let maximumFrames: Int
    init(version: Int = 1, maximumFrames: Int = 3) {
        self.version = version; self.maximumFrames = maximumFrames
    }
    func validate() throws {
        guard version == 1, maximumFrames == 3 else {
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
    let decryptUS: UInt32?
    var data: Data {
        var result = Data(); result.appendBE(id)
        result.appendBE(dispatchUS); result.appendBE(sampleUS); result.appendBE(rendererWaitUS)
        if let decryptUS { result.appendBE(decryptUS) }
        return result
    }
    init(id: UInt64, dispatchUS: UInt32, sampleUS: UInt32, rendererWaitUS: UInt32, decryptUS: UInt32? = nil) {
        self.id = id; self.dispatchUS = dispatchUS; self.sampleUS = sampleUS; self.rendererWaitUS = rendererWaitUS; self.decryptUS = decryptUS
    }
    init(_ data: Data) throws {
        guard [20, 24].contains(data.count), data.uint64BE() > 0 else { throw PairError.message("Invalid video acknowledgement") }
        id = data.uint64BE(); dispatchUS = data.uint32BE(at: 8)
        sampleUS = data.uint32BE(at: 12); rendererWaitUS = data.uint32BE(at: 16)
        decryptUS = data.count == 24 ? data.uint32BE(at: 20) : nil
    }
}

/// Credits cover encoding, TCP and receiver submission together. Only raw
/// captures can be replaced; an encoded predictive frame is never discarded.
struct VideoFrameWindow {
    struct Entry { let capturedAt: UInt64; let sourceAt: UInt64?; let sampleAt: UInt64?; var encodedAt: UInt64? }
    private(set) var limit: Int
    private var nextID: UInt64 = 1
    private(set) var entries: [UInt64: Entry] = [:]
    init(limit: Int) { self.limit = limit }
    mutating func setLimit(_ value: Int) {
        precondition((1...3).contains(value)); limit = value
    }
    var count: Int { entries.count }
    var available: Bool { entries.count < limit }
    var oldest: UInt64? { entries.values.map(\.capturedAt).min() }
    mutating func reserve(capturedAt: UInt64, sourceAt: UInt64? = nil, sampleAt: UInt64? = nil) -> UInt64? {
        guard available, nextID < UInt64.max else { return nil }
        let id = nextID; nextID += 1
        entries[id] = Entry(capturedAt: capturedAt, sourceAt: sourceAt, sampleAt: sampleAt, encodedAt: nil); return id
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
        return values.isEmpty ? 0 : values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
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
    private var recordingStart: UInt64?
    private var recordingCounts: [String: Int] = [:]
    private var recordingTimes: [String: [Double]] = [:]
    private var recordingPeak = 0
    private var recordingDurations: [String: UInt64] = [:]
    private var creditBlocked = false
    private var recordingBlockedAt: UInt64?
    func event(_ key: String, count: Int = 1) {
        lock.withLock {
            counts[key, default: 0] += count; totals[key, default: 0] += count
            if recordingStart != nil { recordingCounts[key, default: 0] += count }
        }
    }
    func setCreditBlocked(_ value: Bool) {
        lock.withLock {
            guard creditBlocked != value else { return }
            creditBlocked = value
            if recordingStart != nil {
                if value { recordingBlockedAt = VideoClock.now }
                else if let at = recordingBlockedAt {
                    recordingDurations["creditStall", default: 0] += VideoClock.now - at; recordingBlockedAt = nil
                }
            }
        }
    }
    func beginRecording() {
        lock.withLock {
            recordingCounts.removeAll(); recordingTimes.removeAll(); recordingDurations.removeAll()
            recordingPeak = outstanding; recordingStart = VideoClock.now
            recordingBlockedAt = creditBlocked ? recordingStart : nil
        }
    }
    func finishRecording() -> VideoTrialMeasurements {
        lock.withLock {
            let now = VideoClock.now
            if let at = recordingBlockedAt { recordingDurations["creditStall", default: 0] += now - at }
            recordingBlockedAt = nil
            let result = VideoTrialMeasurements(seconds: Double(now - (recordingStart ?? now)) / 1e9,
                counts: recordingCounts, times: recordingTimes.mapValues(VideoTiming.init),
                peakOutstanding: recordingPeak, durationsMS: recordingDurations.mapValues { Double($0) / 1e6 })
            recordingStart = nil; recordingCounts.removeAll(); recordingTimes.removeAll(); recordingDurations.removeAll()
            return result
        }
    }
    func timing(_ key: String, ns: UInt64) { timing(key, milliseconds: Double(ns) / 1e6) }
    func timing(_ key: String, milliseconds value: Double) {
        guard value.isFinite else { return }
        lock.withLock {
            if recordingStart != nil, recordingTimes[key, default: []].count < 12_000 {
                recordingTimes[key, default: []].append(value)
            }
            times[key, default: []].append(value)
            if times[key, default: []].count > 120 { times[key]?.removeFirst() }
        }
    }
    func depth(_ value: Int) { lock.withLock { outstanding = value; peakOutstanding = max(peakOutstanding, value); if recordingStart != nil { recordingPeak = max(recordingPeak, value) } } }
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

struct VideoTiming: Codable {
    let count: Int
    let mean: Double?
    let p95: Double?
    init(_ values: [Double]) {
        count = values.count
        mean = values.isEmpty ? nil : values.reduce(0,+) / Double(values.count)
        p95 = values.isEmpty ? nil : values.sorted()[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
    }
}

struct VideoTrialMeasurements: Codable {
    let seconds: Double
    let counts: [String: Int]
    let times: [String: VideoTiming]
    let peakOutstanding: Int
    let durationsMS: [String: Double]
    func rate(_ key: String) -> Double { Double(counts[key, default: 0]) / max(seconds, 0.001) }
    func coverage(_ key: String) -> Double {
        let expected = ["captureAge", "sampleAge"].contains(key) ? counts["capture", default: 0] : counts["ack", default: 0]
        return min(1, Double(times[key]?.count ?? 0) / Double(max(1, expected)))
    }
    func reliableP95(_ key: String) -> Double? {
        if ["sourceAck", "captureAge", "sampleAge", "sampleAck"].contains(key), coverage(key) < 0.9 { return nil }
        return times[key]?.p95
    }
    var creditBlockedFraction: Double { min(1, durationsMS["creditStall", default: 0] / max(1, seconds * 1000)) }
}
