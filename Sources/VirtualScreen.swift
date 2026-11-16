// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

@MainActor
final class VirtualScreen {
    private let native: MPVirtualScreen
    let primaryID: CGDirectDisplayID
    var id: CGDirectDisplayID { native.displayID }
    init(width: Int, height: Int) throws {
        primaryID = CGMainDisplayID()
        guard let native = autoreleasepool(invoking: { MPVirtualScreen(width: UInt(width), height: UInt(height)) }) else {
            throw PairError.message("This system could not create a virtual display (experimental macOS API)")
        }
        self.native = native
    }
    func close() { native.invalidate() }
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
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        guard CGGetActiveDisplayList(32, &ids, &count) == .success else {
            throw PairError.message("Cannot read display arrangement")
        }
        let right = ids.prefix(Int(count)).filter { $0 != id }
            .map { CGDisplayBounds($0).maxX }.max() ?? CGDisplayBounds(primaryID).maxX
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
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            throw PairError.message("macOS rejected the extended display configuration")
        }
        guard CGDisplayIsInMirrorSet(id) == 0 else {
            throw PairError.message("The virtual display is still mirrored")
        }
    }
}
