// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct MacPairApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("MacPair") { MainView(model: model) }
            .defaultSize(width: 740, height: 680)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "display.2").font(.system(size: 34)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacPair").font(.largeTitle.bold())
                        Text(L("Your nearby Mac. Your second display.")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(L("Language"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }.frame(width: 185)
                    Text(L("Prototype 0.1.4")).font(.caption).padding(7).background(.blue.opacity(0.1), in: Capsule())
                }
                Text(L("No router, internet, or Apple ID needed. Keep Wi-Fi on; Bluetooth is recommended."))
                    .font(.callout).foregroundStyle(.secondary)
                Picker(L("This Mac's role"), selection: $model.role) {
                    ForEach(MacRole.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.occupied || model.listening)
                .onChange(of: model.role) { _ in model.stopAll() }

                if model.role == .receiver { receiverPanel } else { hostPanel }

                VStack(alignment: .leading, spacing: 9) {
                    Label(model.status.localized, systemImage: model.connected ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(model.connected ? .green : .primary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(model.path.localized)
                        Spacer()
                        Text(L("Round trip \(model.rtt)"))
                        Text(L("\(model.fps) fps · \(model.totalFrames) frames"))
                    }.font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

                if model.connected {
                    HStack {
                        Button(L("Disconnect")) { model.endSession() }
                        if model.role == .receiver, !model.diagnostic {
                            Button(L("Open display")) { model.showViewer() }
                            Button(L("Full screen")) { model.showViewer(fullscreen: true) }.buttonStyle(.borderedProminent)
                        }
                        if model.role == .host, model.isExtending {
                            Button(L("Arrange displays")) { model.openDisplays() }
                        }
                    }
                }
                DisclosureGroup(L("Diagnostics")) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.events.enumerated()), id: \.offset) { _, text in
                            Text(text.localized).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Button(L("Copy diagnostics")) { model.copyDiagnostics() }.padding(.top, 6)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(L("Up to 30 fps. Mirror uses your main screen; Extend adds a 1280 × 800 desktop."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.frame(minWidth: 700, minHeight: 620)
    }
    private var hostPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(L("Display mode"))
                Picker(L("Display mode"), selection: $model.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(L10n.text(mode.title)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
                .disabled(model.occupied)
                Spacer()
            }
            Text(L(model.displayMode == .mirror
                ? "Mirror shows the host's main screen on the display Mac."
                : "Extend adds a separate desktop; drag windows onto it."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(L("Nearby displays")).font(.headline)
                Spacer()
                Button(L(model.browsing ? "Search again" : "Find nearby displays")) { model.browse() }
                    .disabled(model.occupied)
            }
            if model.peers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if model.browsing {
                        SearchingText(text: L("Looking for displays…"))
                        Text(L("On the other Mac, open MacPair, select Display Mac, and click Wait for connection."))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L("Start waiting on the other Mac, then search here."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(model.peers) { peer in
                            Button { model.selectedID = peer.id } label: {
                                HStack {
                                    Image(systemName: model.selectedID == peer.id ? "largecircle.fill.circle" : "circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(peer.name).lineLimit(1)
                                        Text(L(peer.isDirect
                                            ? "Direct AWDL available · \(peer.interfaces)"
                                            : "Waiting for a direct interface · \(peer.interfaces)"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if peer.isDirect { Image(systemName: "wifi").foregroundStyle(.green) }
                                }.padding(9).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(model.occupied || !peer.isDirect)
                            .background(model.selectedID == peer.id ? .blue.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }.frame(height: 100)
            }
            HStack {
                TextField(L("Pairing code from the display Mac"), text: $model.enteredCode)
                    .textFieldStyle(.roundedBorder).disabled(model.occupied)
                Button(L("Test connection")) { model.connect(testOnly: true) }
                    .disabled(model.occupied || model.selectedPeer?.isDirect != true)
                Button(L(model.displayMode == .mirror ? "Mirror display" : "Extend display")) { model.connect(testOnly: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.occupied || model.selectedPeer?.isDirect != true)
            }
            if !model.permission {
                HStack {
                    Text(L("Screen Recording permission is required on the host.")).font(.caption).foregroundStyle(.secondary)
                    Button(L("Grant Screen Recording")) { model.requestPermission() }
                }
            }
            Text(L("Start with Test connection. Disconnect after it passes, choose a display mode, then start streaming."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var receiverPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Use this Mac as a second display")).font(.headline)
            if model.listening {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Enter this code on the host. A new code is generated each time you start waiting."))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Text(model.pairingCode).font(.system(size: 29, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(L("Stop waiting")) { model.stopAll() }.disabled(model.cleaning)
                    }
                }.padding(16).background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Button(L("Wait for connection")) { model.listen() }
                    .buttonStyle(.borderedProminent).disabled(model.occupied)
            }
            Text(L("The display Mac needs no Screen Recording permission. Its video window opens automatically. Double-click for full screen; press Esc to exit."))
                .font(.callout).foregroundStyle(.secondary)
            Text(L("Use the host's keyboard and trackpad. Display-side input and audio are not included yet."))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 165, alignment: .top)
    }
}


// A moving highlight over stationary glyphs, matching the search activity cue.
struct SearchingText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var visible = false

    private var label: some View {
        Text(text).font(.callout).fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        label
            .foregroundStyle(.secondary)
            .overlay(alignment: .leading) {
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !visible)) { timeline in
                        let progress = CGFloat(max(0, timeline.date.timeIntervalSince(startedAt))
                            .truncatingRemainder(dividingBy: 2.0) / 2.0)
                        // Paint the highlight in the glyphs' own bounds. Only
                        // their color changes; their layout stays stationary.
                        label.foregroundStyle(LinearGradient(
                            colors: [.clear, .white, .clear],
                            startPoint: UnitPoint(x: progress * 1.8 - 0.8, y: 0.5),
                            endPoint: UnitPoint(x: progress * 1.8, y: 0.5)))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear { startedAt = Date(); visible = true }
            .onDisappear { visible = false }
    }
}
