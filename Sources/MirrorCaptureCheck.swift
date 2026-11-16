// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit

private final class MirrorCaptureProbe: NSObject, SCStreamOutput {
    // The output handler and the checker both run on the main queue.
    var dimensions: (width: Int, height: Int)?
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, dimensions == nil,
              let info = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = info.first?[.status] as? Int,
              SCFrameStatus(rawValue: status) == .complete,
              let image = CMSampleBufferGetImageBuffer(sample) else { return }
        dimensions = (CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image))
    }
}

enum MirrorCaptureCheck {
    @MainActor
    static func run() -> Never {
        guard CGPreflightScreenCaptureAccess() else {
            print("SKIP: Mirror capture requires Screen Recording permission already granted to this app. No permission was requested.")
            exit(77)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let id = CGMainDisplayID()
                let target = try MirrorSizing.dimensions(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id))
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw PairError.message("The main display is no longer available for mirroring")
                }
                let configuration = SCStreamConfiguration()
                configuration.width = target.width
                configuration.height = target.height
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                configuration.capturesAudio = false
                let probe = MirrorCaptureProbe()
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                try stream.addStreamOutput(probe, type: .screen, sampleHandlerQueue: .main)
                do {
                    try await stream.startCapture()
                    for _ in 0..<50 {
                        if probe.dimensions != nil { break }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    try await stream.stopCapture()
                } catch {
                    try? await stream.stopCapture()
                    throw error
                }
                guard let actual = probe.dimensions,
                      actual.width == target.width, actual.height == target.height else {
                    throw PairError.message("Mirror capture did not produce the expected frame size")
                }
                print("PASS: actual main-display capture at \(actual.width)x\(actual.height); no image saved or transmitted")
                exit(0)
            } catch {
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        app.run()
        exit(1)
    }
}
