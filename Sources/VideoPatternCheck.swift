// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import QuartzCore

@MainActor
enum VideoPatternCheck {
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory); app.finishLaunching()
        Task { @MainActor in
            let view = VideoMotionPattern(frame: NSRect(x: 0, y: 0, width: 560, height: 350))
            let window = VideoMotionWindow(contentRect: NSRect(x: 70, y: 70, width: 560, height: 350),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "MacPair · Generated compositor check"
            window.contentView = view; window.orderFrontRegardless()
            do {
                view.beginRecording()
                try await Task.sleep(for: .milliseconds(400))
                let recording = view.finishRecording()
                guard view.animationsScheduled, recording.counts["compositorAnimation"] == 1,
                      recording.counts["timer", default: 0] > 0 else { throw PairError.message("Compositor source did not start") }
                if let index = CommandLine.arguments.firstIndex(of: "--pattern-preview-output"), index + 1 < CommandLine.arguments.count {
                    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1120, pixelsHigh: 700,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let context = NSGraphicsContext(bitmapImageRep: image)!.cgContext
                    context.scaleBy(x: 2, y: 2); view.layer?.render(in: context)
                    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                }
                view.stop()
                guard !view.animationsScheduled else { throw PairError.message("Compositor source did not stop") }
                window.close()
                print("PASS: app-owned compositor animation, main-loop events and cancellation cleanup; no screen capture and no presentation-rate claim")
                exit(0)
            } catch { view.stop(); window.close(); fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        app.run(); exit(1)
    }
}
