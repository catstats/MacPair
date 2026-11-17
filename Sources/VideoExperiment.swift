// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit

struct VideoTrial: Codable {
    let frames: Int
    let queueDepth: Int
    let measurements: VideoTrialMeasurements
    var renderer: VideoRendererInterval? = nil
}

struct VideoRendererStatistics: Codable {
    let at: UInt64
    let total: Int
    let dropped: Int
    let corrupted: Int
    let accumulatedDelayMS: Double
    func validate() throws {
        guard (0...1_000_000_000).contains(total), (0...total).contains(dropped), (0...total).contains(corrupted),
              accumulatedDelayMS.isFinite, accumulatedDelayMS >= 0 else { throw PairError.message("Invalid renderer statistics") }
    }
}
struct VideoRendererInterval: Codable {
    let seconds: Double
    let frames: Int
    let dropped: Int
    let corrupted: Int
    let meanDelayMS: Double
    static func between(_ before: VideoRendererStatistics?, _ after: VideoRendererStatistics?) -> Self? {
        guard let before, let after, after.at > before.at, after.total > before.total,
              after.dropped >= before.dropped, after.corrupted >= before.corrupted,
              after.accumulatedDelayMS >= before.accumulatedDelayMS else { return nil }
        let frames = after.total - before.total
        return Self(seconds: Double(after.at - before.at) / 1e9, frames: frames,
            dropped: after.dropped - before.dropped, corrupted: after.corrupted - before.corrupted,
            meanDelayMS: (after.accumulatedDelayMS - before.accumulatedDelayMS) / Double(frames))
    }
}

struct VideoExperimentReport: Codable {
    var schema = 1
    let created: Date
    let scope: String
    var context: [String: String] = [:]
    let width: Int
    let height: Int
    let targetFPS: Int
    let trials: [VideoTrial]
    let selectedFrames: Int
    let verification: VideoTrial
    let rejectedCandidate: Int?
    let latencyRule: String
    let limitations: [String]
    static let latencyRule = "Reject a candidate if callback-to-submission-ACK p95 exceeds baseline by max(10 ms, 20%); require >=10% FPS gain, or for one frame >=95% baseline FPS (baseline >=30) with >=20% lower ACK p95. Defaults remain unchanged outside this session."
    static let limitations = [
        "ACK ends at AVSampleBufferDisplayLayer enqueue, includes return trip, and is not physical presentation latency.",
        "One-way wireless delay is not measured: clocks on the two Macs are not synchronized.",
        "Decode and physical-display p95 are unavailable from the production display-layer path; codec-only decode is measured separately.",
        "FPS is submission/ACK throughput. Static content and insufficient source updates cannot establish the maximum stream rate."]
    static func choose(_ trials: [VideoTrial]) -> Int {
        func aggregate(_ frames: Int) -> (fps: Double, p95: Double)? {
            let records = trials.filter { $0.frames == frames && $0.measurements.counts["ack", default: 0] >= 30 }
            guard records.count >= 2, records.allSatisfy({ $0.measurements.rate("capture") >= 30 }),
                  records.allSatisfy({ $0.measurements.times["ack"]?.p95 != nil }) else { return nil }
            let rates = records.map { $0.measurements.rate("ack") }
            guard let slowest = rates.min(), let fastest = rates.max(), fastest <= slowest * 1.25,
                  records.allSatisfy({ $0.renderer?.corrupted == nil || $0.renderer?.corrupted == 0 }),
                  records.allSatisfy({ ($0.renderer.map { Double($0.dropped) / Double(max(1, $0.frames)) } ?? 0) <= 0.02 }) else { return nil }
            return (rates.reduce(0,+) / Double(records.count),
                records.compactMap { $0.measurements.times["ack"]?.p95 }.max()!)
        }
        guard let baseline = aggregate(2) else { return 2 }
        var best = 2, bestFPS = baseline.fps
        for frames in [1, 3] {
            guard let candidate = aggregate(frames),
                  candidate.p95 <= baseline.p95 + max(10, baseline.p95 * 0.2) else { continue }
            let faster = candidate.fps >= baseline.fps * 1.1 && candidate.fps > bestFPS
            let lowerLatency = frames == 1 && baseline.fps >= 30 && candidate.fps >= baseline.fps * 0.95 && candidate.p95 <= baseline.p95 * 0.8
            guard faster || lowerLatency else { continue }
            let sourceBaseline = trials.filter { $0.frames == 2 }.compactMap { $0.measurements.times["sourceAck"]?.p95 }.max()
            let sourceCandidate = trials.filter { $0.frames == frames }.compactMap { $0.measurements.times["sourceAck"]?.p95 }.max()
            if let sourceBaseline, let sourceCandidate, sourceCandidate > sourceBaseline + max(10, sourceBaseline * 0.2) { continue }
            let baselineGap = trials.filter { $0.frames == 2 }.compactMap { $0.measurements.times["ackInterval"]?.p95 }.max()
            let candidateGap = trials.filter { $0.frames == frames }.compactMap { $0.measurements.times["ackInterval"]?.p95 }.max()
            if let baselineGap, let candidateGap, candidateGap > baselineGap + max(5, baselineGap * 0.2) { continue }
            best = frames; bestFPS = candidate.fps
        }
        return best
    }
    static func verificationPasses(_ trial: VideoTrial, baseline: [VideoTrial]) -> Bool {
        let records = baseline.filter { $0.frames == 2 }
        guard let baselineP95 = records.compactMap({ $0.measurements.times["ack"]?.p95 }).max(),
              let actualP95 = trial.measurements.times["ack"]?.p95,
              actualP95 <= baselineP95 + max(10, baselineP95 * 0.2),
              trial.measurements.counts["ack", default: 0] >= 30 else { return false }
        if let baseSource = records.compactMap({ $0.measurements.times["sourceAck"]?.p95 }).max(),
           let source = trial.measurements.times["sourceAck"]?.p95, source > baseSource + max(10, baseSource * 0.2) { return false }
        let baseFPS = records.map { $0.measurements.rate("ack") }.reduce(0,+) / Double(max(1, records.count))
        let faster = trial.measurements.rate("ack") >= baseFPS * 1.1
        let lowerLatency = trial.frames == 1 && baseFPS >= 30 && trial.measurements.rate("ack") >= baseFPS * 0.95 && actualP95 <= baselineP95 * 0.8
        guard trial.frames == 2 || faster || lowerLatency else { return false }
        if let baseGap = records.compactMap({ $0.measurements.times["ackInterval"]?.p95 }).max(),
           let gap = trial.measurements.times["ackInterval"]?.p95, gap > baseGap + max(5, baseGap * 0.2) { return false }
        if let renderer = trial.renderer, renderer.corrupted > 0 || Double(renderer.dropped) / Double(max(1, renderer.frames)) > 0.02 { return false }
        return true
    }
    var text: String {
        var lines = ["\(width) × \(height) px · \(targetFPS) fps target · SCK queue 3",
            "frames | ACK fps | capture fps | ACK p95 ms | source→ACK p95 ms | encode p95 ms | credit blocked"]
        for t in trials {
            func p(_ key: String) -> String { t.measurements.times[key]?.p95.map { String(format: "%.1f", $0) } ?? "unavailable" }
            lines.append("\(t.frames) | \(String(format: "%.1f", t.measurements.rate("ack"))) | \(String(format: "%.1f", t.measurements.rate("capture"))) | \(p("ack")) | \(p("sourceAck")) | \(p("encode")) | \(String(format: "%.0f%%", t.measurements.creditBlockedFraction * 100))")
        }
        let baselineFPS = trials.filter { $0.frames == 2 }.map { $0.measurements.rate("ack") }.reduce(0,+) / Double(max(1, trials.filter { $0.frames == 2 }.count))
        lines.append("Before → verified after: \(String(format: "%.1f", baselineFPS)) → \(String(format: "%.1f", verification.measurements.rate("ack"))) ACK fps")
        lines.append("Pipeline p95 ms (worst baseline run → independent verification):")
        for key in ["captureAge", "captureInterval", "ackInterval", "raw", "encode", "sendQueue", "encrypt", "localTransport", "afterEncodeAck", "decrypt", "dispatch", "sample", "renderer", "ack", "sourceAck"] {
            let before = trials.filter { $0.frames == 2 }.compactMap { $0.measurements.times[key]?.p95 }.max()
            let after = verification.measurements.times[key]?.p95
            func number(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "unavailable" }
            lines.append("\(key): \(number(before)) → \(number(after))")
        }
        lines.append("Selected \(selectedFrames) frame(s) for this session. " + Self.latencyRule)
        if let rejectedCandidate { lines.append("Verification rejected \(rejectedCandidate) frame(s); restored two-frame default.") }
        if let renderer = verification.renderer {
            lines.append("Renderer estimate: \(String(format: "%.1f", Double(renderer.frames - renderer.dropped) / renderer.seconds)) fps, \(renderer.dropped) dropped; mean scheduled-time delay \(String(format: "%.1f", renderer.meanDelayMS)) ms. Not optical latency.")
        } else { lines.append("Renderer presentation statistics: unavailable (not zero).") }
        lines.append(contentsOf: Self.limitations)
        return lines.joined(separator: "\n")
    }
}

/// Repeatable, app-owned moving document. Pixels never enter the report.
@MainActor
final class VideoMotionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class VideoMotionPattern: NSView {
    private var timer: Timer?
    private let started = ProcessInfo.processInfo.systemUptime
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        RunLoop.main.add(timer!, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) } }
    override func mouseDown(with event: NSEvent) { onCancel?() }
    func stop() { timer?.invalidate(); timer = nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); bounds.fill()
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let inset: CGFloat = 40
        let offset = CGFloat(elapsed * 180).truncatingRemainder(dividingBy: 30)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular), .foregroundColor: NSColor.darkGray]
        for row in -1...Int(bounds.height / 30) {
            let y = CGFloat(row) * 30 - offset
            "MacPair  ·  scrolling document  ·  Retina pixels  ·  line \(row + Int(elapsed * 6))".draw(at: NSPoint(x: inset, y: y), withAttributes: attributes)
        }
        let x = inset + (bounds.width - inset * 2 - 280) * CGFloat((sin(elapsed * 1.7) + 1) / 2)
        let y = bounds.height * 0.45 + CGFloat(sin(elapsed * 1.1) * 70)
        let card = NSRect(x: x, y: y, width: 280, height: 150)
        NSColor.systemBlue.setFill(); NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
        L("MacPair smoothness test").draw(at: NSPoint(x: card.minX + 18, y: card.minY + 24), withAttributes: [.font: NSFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: NSColor.white])
        L("Click or press Esc to cancel").draw(at: NSPoint(x: card.minX + 18, y: card.minY + 76), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white])
    }
}
