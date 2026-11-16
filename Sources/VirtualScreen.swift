// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

@MainActor
final class VirtualScreen {
    private let native: MPVirtualScreen
    let primaryID: CGDirectDisplayID
    var id: CGDirectDisplayID { native.displayID }
    let canvas: VirtualCanvas
    private var modeMonitor: Task<Void, Never>?
    var onError: ((LocalizedMessage) -> Void)?
    init(width: Int, height: Int, scale: Int = 1, serial: UInt32 = 0x4D500001) throws {
        canvas = VirtualCanvas(width: width, height: height, scale: scale)
        try canvas.validate()
        primaryID = CGMainDisplayID()
        guard let native = autoreleasepool(invoking: { MPVirtualScreen(width: UInt(width), height: UInt(height), scale: UInt(scale), serial: serial) }) else {
            throw PairError.message("This system could not create a virtual display (experimental macOS API)")
        }
        self.native = native
    }
    func close() {
        modeMonitor?.cancel()
        modeMonitor = nil
        native.invalidate()
    }
    private var modeMatches: Bool {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return false }
        return mode.width == canvas.width && mode.height == canvas.height
            && mode.pixelWidth == canvas.pixelWidth && mode.pixelHeight == canvas.pixelHeight
    }
    private func selectMode() throws {
        if modeMatches { return }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode],
              let mode = modes.first(where: {
                  $0.width == canvas.width && $0.height == canvas.height
                      && $0.pixelWidth == canvas.pixelWidth && $0.pixelHeight == canvas.pixelHeight
              }) else { throw PairError.message("macOS did not offer the requested Retina display mode") }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw PairError.message("Cannot configure display arrangement")
        }
        guard CGConfigureDisplayWithDisplayMode(config, id, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            throw PairError.message("macOS rejected the requested Retina display mode")
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            throw PairError.message("macOS rejected the requested Retina display mode")
        }
    }
    static func isOnline(_ id: CGDirectDisplayID) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        return CGGetOnlineDisplayList(32, &ids, &count) == .success
            && ids.prefix(Int(count)).contains(id)
    }
    func arrange() async throws {
        for _ in 0..<30 {
            if Self.isOnline(id) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard Self.isOnline(id), id != primaryID else {
            throw PairError.message("The virtual display did not come online")
        }
        // applySettings can expose both 1× and 2× modes. Select and verify
        // logical AND backing dimensions rather than trusting its default.
        for attempt in 0..<30 {
            try Task.checkCancellation()
            do { try selectMode() } catch { if attempt == 29 { throw error } }
            if modeMatches { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard modeMatches else { throw PairError.message("macOS rejected the requested Retina display mode") }
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        guard CGGetActiveDisplayList(32, &ids, &count) == .success else {
            throw PairError.message("Cannot read display arrangement")
        }
        let right = ids.prefix(Int(count)).filter { $0 != id }
            .map { CGDisplayBounds($0).maxX }.max() ?? CGDisplayBounds(primaryID).maxX
        if CommandLine.arguments.contains("--trace") {
            print("TRACE arrange id=\(id) primary=\(primaryID) active=\(Array(ids.prefix(Int(count)))) right=\(right) bounds=\(CGDisplayBounds(id)) mirrored=\(CGDisplayIsInMirrorSet(id))")
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw PairError.message("Cannot configure display arrangement")
        }
        let mirror = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        let origin = CGConfigureDisplayOrigin(config, id, Int32(right), 0)
        guard mirror == .success, origin == .success else {
            CGCancelDisplayConfiguration(config)
            throw PairError.message("Cannot enable the extended desktop")
        }
        let result = CGCompleteDisplayConfiguration(config, .forSession)
        guard result == .success else {
            throw PairError.message("macOS rejected the extended display configuration (\(result.rawValue))")
        }
        guard CGDisplayIsInMirrorSet(id) == 0 else {
            throw PairError.message("The virtual display is still mirrored")
        }
        // WindowServer may restore a saved 1× mode after initial setup.
        // Reassert this session's geometry without changing the user's origin.
        modeMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard let self, !Task.isCancelled else { return }
                do { try self.selectMode() }
                catch { self.onError?(error.appMessage); return }
            }
        }
    }
}
