// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

/// A normal app-owned panel. Showing it never makes it key or activates MacPair.
final class NearbyDisplayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor
    static func make<Content: View>(remembered: Bool, content: Content) -> NearbyDisplayPanel {
        let size = NSSize(width: 360, height: remembered ? 350 : 400)
        let panel = NearbyDisplayPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L("MacPair · Nearby display")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: content)
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 24, y: frame.minY + 24))
        }
        return panel
    }
}

struct NearbyDisplayCard: View {
    let name: String
    let remembered: Bool
    @Binding var mode: DisplayMode
    @Binding var code: String
    let connect: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "display.2").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacPair").font(.headline)
                    Text(L("Nearby Mac detected")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help(L("Not now"))
                    .accessibilityLabel(L("Not now")).keyboardShortcut(.cancelAction)
            }
            VStack(spacing: 9) {
                Image(systemName: "laptopcomputer").font(.system(size: 44, weight: .light))
                Text(name).font(.title3.bold()).lineLimit(2).multilineTextAlignment(.center)
                Text(L("Available as a second display")).font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            Picker(L("Display mode"), selection: $mode) {
                ForEach(DisplayMode.allCases) { Text(L10n.text($0.title)).tag($0) }
            }.pickerStyle(.menu)
            if remembered {
                Label(L("Paired · No code needed"), systemImage: "lock.fill").font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Pairing code")).font(.caption).foregroundStyle(.secondary)
                    TextField(L("Six digits from the display Mac"), text: $code)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Button(action: connect) {
                Text(L("Connect")).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!remembered && !PairingCode.isValid(code))
        }
        .padding(22)
        .frame(width: 360, height: remembered ? 350 : 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
    }
}

@MainActor
struct SuggestedDisplayCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let peer = model.suggestedPeer {
            NearbyDisplayCard(name: peer.displayName, remembered: model.isTrusted(peer),
                mode: $model.displayMode, code: $model.enteredCode,
                connect: { model.connectSuggestedDisplay() },
                dismiss: { model.dismissSuggestion() })
        }
    }
}
