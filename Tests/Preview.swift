import AppKit
import SwiftUI

// Component previews only. These fixtures do not start device discovery.
@main
enum Preview {
    @MainActor static func main() {
        let searching = CommandLine.arguments.contains("--searching")
        let mirrorMode = CommandLine.arguments.contains("--mirror")
        let app = NSApplication.shared
        let appearance: NSAppearance.Name = searching ? .darkAqua : .aqua
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: appearance)
        app.finishLaunching()
        let original = UserDefaults.standard.object(forKey: L10n.preferenceKey)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for language in AppLanguage.allCases {
                for receiver in ((searching || mirrorMode) ? [false] : [false, true]) {
                    let model = AppModel()
                    model.language = language
                    if mirrorMode { model.displayMode = .mirror }
                    if searching {
                        model.browsing = true
                        model.status = "Looking for nearby displays… Keep Wi-Fi on on both Macs."
                    } else if receiver {
                        model.role = .receiver
                        model.listening = true
                        model.pairingCode = "ABCD-EFGH-JKLM"
                        model.status = "Waiting for the host. Select this Mac on the host and enter the pairing code below."
                    }
                    let hosting = NSHostingView(rootView: MainView(model: model)
                        .environment(\.colorScheme, searching ? .dark : .light)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
                    let window = NSWindow(contentRect: hosting.frame,
                        styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.title = searching ? "MacPair search highlight preview" : "MacPair layout fixture"
                    window.contentView = hosting
                    window.center()
                    window.appearance = NSAppearance(named: appearance)
                    window.makeKeyAndOrderFront(nil)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                    let prefix = (searching ? "search-" : (mirrorMode ? "host-mirror-" : (receiver ? "display-" : "host-"))) + language.rawValue
                    for frame in (searching ? [1, 2] : [1]) {
                        if frame == 2 { RunLoop.main.run(until: Date().addingTimeInterval(0.9)) }
                        hosting.layoutSubtreeIfNeeded()
                        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                            throw PairError.message("Cannot allocate preview bitmap")
                        }
                        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                        guard let data = bitmap.representation(using: .png, properties: [:]) else {
                            throw PairError.message("Cannot render preview PNG")
                        }
                        let name = prefix + (searching ? "-\(frame)" : "") + ".png"
                        try data.write(to: output.appendingPathComponent(name))
                        print("Rendered " + name)
                    }
                    window.close()
                }
            }
            if let original { UserDefaults.standard.set(original, forKey: L10n.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: L10n.preferenceKey) }
            exit(0)
        } catch {
            fputs("Preview failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
