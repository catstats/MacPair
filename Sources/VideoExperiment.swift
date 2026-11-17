// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import QuartzCore
import CoreText

struct VideoTrial: Codable {
    let frames: Int
    let queueDepth: Int
    let measurements: VideoTrialMeasurements
    var renderer: VideoRendererInterval? = nil
    var pattern: VideoTrialMeasurements? = nil
    var streamingActivity: Bool? = nil
    var hasContinuousPattern: Bool {
        pattern?.counts["compositorAnimation"] == 1 || (pattern?.rate("draw") ?? 0) >= 40
    }
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
    var schema = 2
    let created: Date
    let scope: String
    var context: [String: String] = [:]
    let width: Int
    let height: Int
    let targetFPS: Int
    let trials: [VideoTrial]
    let selectedFrames: Int
    var comparisonKind: String = "frameWindow"
    var selectedQueueDepth: Int = 3
    var selectedStreamingActivity: Bool = true
    let verification: VideoTrial
    let rejectedCandidate: Int?
    let latencyRule: String
    let limitations: [String]
    static let latencyRule = "Reject a candidate if callback-to-submission-ACK p95 exceeds baseline by max(10 ms, 20%); require >=10% FPS gain, or for one frame >=95% baseline FPS (baseline >=30) with >=20% lower ACK p95. Defaults remain unchanged outside this session."
    static let captureLatencyRule = "Compare RC1-equivalent activity-off/queue-3 against protected activity/queue-3 and protected activity/queue-5. Activity protection may remain at >=95% baseline FPS only with the same latency guards. Queue 5 requires >=10% ACK FPS gain, a continuous compositor source (or >=40 measured draws/s), consistent repeats, >=90% capture-PTS coverage, no substantial ACK/cadence/age p95 regression and no renderer corruption or >2% drops. Failed verification restores queue 3."
    static let limitations = [
        "ACK ends at AVSampleBufferDisplayLayer enqueue, includes return trip, and is not physical presentation latency.",
        "One-way wireless delay is not measured: clocks on the two Macs are not synchronized.",
        "Decode and physical-display p95 are unavailable from the production display-layer path; codec-only decode is measured separately.",
        "Sample PTS is checked against the local host clock; invalid/out-of-range samples remain unavailable. Timestamp deltas are signed: a reported presentation timestamp may lead the callback; this is not optical latency.",
        "WindowServer p95 is unavailable when timestamp coverage is below 90%; raw per-key samples retain their counts.",
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
            let sourceBaseline = trials.filter { $0.frames == 2 }.compactMap { $0.measurements.reliableP95("sourceAck") }.max()
            let sourceCandidate = trials.filter { $0.frames == frames }.compactMap { $0.measurements.reliableP95("sourceAck") }.max()
            if let sourceBaseline, let sourceCandidate, sourceCandidate > sourceBaseline + max(10, sourceBaseline * 0.2) { continue }
            let baselineGap = trials.filter { $0.frames == 2 }.compactMap { $0.measurements.times["ackInterval"]?.p95 }.max()
            let candidateGap = trials.filter { $0.frames == frames }.compactMap { $0.measurements.times["ackInterval"]?.p95 }.max()
            if let baselineGap, let candidateGap, candidateGap > baselineGap + max(5, baselineGap * 0.2) { continue }
            best = frames; bestFPS = candidate.fps
        }
        return best
    }
    static func chooseCaptureDepth(_ trials: [VideoTrial]) -> Int {
        func aggregate(_ depth: Int) -> (fps: Double, ack: Double, age: Double, gap: Double)? {
            let records = trials.filter { $0.queueDepth == depth }
            guard records.count >= 2,
                  records.allSatisfy({ $0.hasContinuousPattern }),
                  records.allSatisfy({ $0.measurements.reliableP95("sampleAge") != nil }),
                  records.allSatisfy({ $0.measurements.times["ack"]?.p95 != nil }),
                  records.allSatisfy({ $0.renderer?.corrupted == nil || $0.renderer?.corrupted == 0 }),
                  records.allSatisfy({ ($0.renderer.map { Double($0.dropped) / Double(max(1, $0.frames)) } ?? 0) <= 0.02 }) else { return nil }
            let rates = records.map { $0.measurements.rate("ack") }
            guard rates.max()! <= rates.min()! * 1.25 else { return nil }
            return (rates.reduce(0,+) / Double(records.count), records.compactMap { $0.measurements.times["ack"]?.p95 }.max()!,
                records.compactMap { $0.measurements.reliableP95("sampleAge") }.max()!, records.compactMap { $0.measurements.times["ackInterval"]?.p95 }.max() ?? 0)
        }
        guard let baseline = aggregate(3), let candidate = aggregate(5), candidate.fps >= baseline.fps * 1.1,
              candidate.ack <= baseline.ack + max(10, baseline.ack * 0.2),
              candidate.age <= baseline.age + max(5, baseline.age * 0.2),
              candidate.gap <= baseline.gap + max(5, baseline.gap * 0.2) else { return 3 }
        return 5
    }
    static func chooseCaptureProfile(_ trials: [VideoTrial]) -> (activity: Bool, depth: Int) {
        let baseline = trials.filter { $0.queueDepth == 3 && $0.streamingActivity == false }
        let protected = trials.filter { $0.streamingActivity == true }
        let q3 = protected.filter { $0.queueDepth == 3 }
        guard baseline.count >= 2, q3.count >= 2 else { return (false, 3) }
        func stable(_ records: [VideoTrial]) -> Bool {
            let rates = records.map { $0.measurements.rate("ack") }
            return rates.min()! >= 3 && rates.max()! <= rates.min()! * 1.25
        }
        var result = (activity: false, depth: 3)
        if stable(baseline), stable(q3), q3.allSatisfy({ verifyCaptureProfile($0, baseline: baseline) }) { result = (true, 3) }
        if stable(baseline), chooseCaptureDepth(protected) == 5 {
            let q5 = protected.filter { $0.queueDepth == 5 }
            if q5.allSatisfy({ verifyCaptureDepth($0, baseline: baseline) }) { result = (true, 5) }
        }
        return result
    }
    static func verifyCaptureProfile(_ trial: VideoTrial, baseline: [VideoTrial]) -> Bool {
        if trial.queueDepth == 5 { return verifyCaptureDepth(trial, baseline: baseline) }
        guard let baseAge = baseline.compactMap({ $0.measurements.reliableP95("sampleAge") }).max(),
              let age = trial.measurements.reliableP95("sampleAge"), age <= baseAge + max(5, baseAge * 0.2),
              trial.hasContinuousPattern else { return false }
        let baseFPS = baseline.map { $0.measurements.rate("ack") }.reduce(0,+) / Double(max(1, baseline.count))
        return trial.measurements.rate("ack") >= baseFPS * 0.95 && verificationPasses(trial, baseline: baseline)
    }
    static func verifyCaptureDepth(_ trial: VideoTrial, baseline: [VideoTrial]) -> Bool {
        guard let baseAge = baseline.compactMap({ $0.measurements.reliableP95("sampleAge") }).max(),
              let age = trial.measurements.reliableP95("sampleAge"), age <= baseAge + max(5, baseAge * 0.2),
              trial.hasContinuousPattern else { return false }
        let baseFPS = baseline.map { $0.measurements.rate("ack") }.reduce(0,+) / Double(max(1, baseline.count))
        return trial.measurements.rate("ack") >= baseFPS * 1.1 && verificationPasses(trial, baseline: baseline)
    }
    static func verificationPasses(_ trial: VideoTrial, baseline: [VideoTrial]) -> Bool {
        let records = baseline.filter { $0.frames == 2 }
        guard let baselineP95 = records.compactMap({ $0.measurements.times["ack"]?.p95 }).max(),
              let actualP95 = trial.measurements.times["ack"]?.p95,
              actualP95 <= baselineP95 + max(10, baselineP95 * 0.2),
              trial.measurements.counts["ack", default: 0] >= 30 else { return false }
        if let baseSource = records.compactMap({ $0.measurements.reliableP95("sourceAck") }).max(),
           let source = trial.measurements.reliableP95("sourceAck"), source > baseSource + max(10, baseSource * 0.2) { return false }
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
        var lines = ["\(width) × \(height) px · \(targetFPS) fps target · SCK queue \(selectedQueueDepth) · activity \(selectedStreamingActivity ? "protected" : "RC1-equivalent")",
            "frames | queue | activity | ACK fps | capture fps | ACK p95 ms | source→ACK p95 ms | encode p95 ms | credit blocked"]
        for t in trials {
            func p(_ key: String) -> String { t.measurements.reliableP95(key).map { String(format: "%.1f", $0) } ?? "unavailable" }
            if let pattern = t.pattern {
                if pattern.counts["compositorAnimation"] == 1 {
                    lines.append("Pattern: compositor animation scheduled; main timer \(String(format: "%.1f", pattern.rate("timer"))) ticks/s. Compositor presentation rate is unreported.")
                } else {
                    lines.append("Pattern timer/draw: \(String(format: "%.1f", pattern.rate("timer")))/\(String(format: "%.1f", pattern.rate("draw"))) fps; draw p95 \(String(format: "%.2f", pattern.times["draw"]?.p95 ?? 0)) ms")
                }
            }
            lines.append("WindowServer timestamp coverage: \(String(format: "%.0f", t.measurements.coverage("sourceAck") * 100))%")
            lines.append("\(t.frames) | \(t.queueDepth) | \(t.streamingActivity.map { $0 ? "on" : "off" } ?? "unknown") | \(String(format: "%.1f", t.measurements.rate("ack"))) | \(String(format: "%.1f", t.measurements.rate("capture"))) | \(p("ack")) | \(p("sourceAck")) | \(p("encode")) | \(String(format: "%.0f%%", t.measurements.creditBlockedFraction * 100))")
        }
        let baselineFPS = trials.filter { comparisonKind == "captureQueue" ? ($0.queueDepth == 3 && $0.streamingActivity == false) : $0.frames == 2 }.map { $0.measurements.rate("ack") }.reduce(0,+) / Double(max(1, trials.filter { comparisonKind == "captureQueue" ? ($0.queueDepth == 3 && $0.streamingActivity == false) : $0.frames == 2 }.count))
        lines.append("Before → verified after: \(String(format: "%.1f", baselineFPS)) → \(String(format: "%.1f", verification.measurements.rate("ack"))) ACK fps")
        lines.append("Pipeline p95 ms (worst baseline run → independent verification):")
        for key in ["captureAge", "sampleAge", "sampleAck", "captureInterval", "ackInterval", "raw", "encode", "sendQueue", "encrypt", "localTransport", "afterEncodeAck", "decrypt", "dispatch", "sample", "renderer", "ack", "sourceAck"] {
            let before = trials.filter { comparisonKind == "captureQueue" ? ($0.queueDepth == 3 && $0.streamingActivity == false) : $0.frames == 2 }.compactMap { $0.measurements.reliableP95(key) }.max()
            let after = verification.measurements.reliableP95(key)
            func number(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "unavailable" }
            lines.append("\(key): \(number(before)) → \(number(after))")
        }
        lines.append("Selected SCK queue \(selectedQueueDepth).")
        lines.append("Selected \(selectedFrames) frame(s) for this session. " + latencyRule)
        if let rejectedCandidate { lines.append("Verification rejected \(comparisonKind == "captureQueue" ? "capture queue" : "frame window") \(rejectedCandidate); restored defaults.") }
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
    private let metrics = VideoMetrics()
    private let document = CATextLayer()
    private let card = CALayer()
    private var sceneSize = NSSize.zero
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildScene()
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.metrics.event("timer") }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() { super.layout(); if sceneSize != bounds.size { buildScene() } }
    private func textLayer(_ text: String, size: CGFloat, frame: NSRect, color: NSColor) -> CATextLayer {
        let result = CATextLayer(); result.string = text; result.frame = frame
        result.font = CTFontCreateWithName("Menlo" as CFString, size, nil); result.fontSize = size
        result.foregroundColor = color.cgColor; result.contentsScale = window?.backingScaleFactor ?? 2
        result.isWrapped = false; return result
    }
    private func buildScene() {
        guard let root = layer, bounds.width > 0, bounds.height > 0 else { return }
        sceneSize = bounds.size
        root.sublayers = nil; root.isGeometryFlipped = true
        root.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1).cgColor
        document.removeAllAnimations(); card.removeAllAnimations(); card.sublayers = nil
        document.string = (0..<(Int(bounds.height / 28) + 16)).map { "MacPair  ·  Retina scrolling document  ·  line \($0)" }.joined(separator: "\n")
        document.font = CTFontCreateWithName("Menlo" as CFString, 15, nil); document.fontSize = 15
        document.foregroundColor = NSColor.darkGray.cgColor; document.contentsScale = window?.backingScaleFactor ?? 2
        document.frame = NSRect(x: 40, y: -100, width: bounds.width - 80, height: bounds.height + 300)
        root.addSublayer(document)
        let scroll = CABasicAnimation(keyPath: "position.y")
        scroll.fromValue = document.position.y; scroll.toValue = document.position.y - 56
        scroll.duration = 56.0 / 180.0; scroll.repeatCount = .infinity
        scroll.timingFunction = CAMediaTimingFunction(name: .linear)
        document.add(scroll, forKey: "scroll")
        card.frame = NSRect(x: 40, y: bounds.height * 0.4, width: 300, height: 150)
        card.backgroundColor = NSColor.systemBlue.cgColor; card.cornerRadius = 14; card.isGeometryFlipped = true
        card.addSublayer(textLayer(L("MacPair smoothness test"), size: 17, frame: NSRect(x: 18, y: 28, width: 270, height: 28), color: .white))
        card.addSublayer(textLayer(L("Click or press Esc to cancel"), size: 14, frame: NSRect(x: 18, y: 78, width: 270, height: 28), color: .white))
        root.addSublayer(card)
        let horizontal = CABasicAnimation(keyPath: "position.x")
        horizontal.fromValue = card.position.x; horizontal.toValue = max(card.position.x, bounds.width - 190)
        horizontal.duration = 2; horizontal.autoreverses = true; horizontal.repeatCount = .infinity
        card.add(horizontal, forKey: "move")
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) } }
    override func mouseDown(with event: NSEvent) { onCancel?() }
    func stop() { timer?.invalidate(); timer = nil; document.removeAllAnimations(); card.removeAllAnimations() }
    var animationsScheduled: Bool { document.animation(forKey: "scroll") != nil && card.animation(forKey: "move") != nil }
    func beginRecording() { metrics.beginRecording(); if animationsScheduled { metrics.event("compositorAnimation") } }
    func finishRecording() -> VideoTrialMeasurements { metrics.finishRecording() }
}
