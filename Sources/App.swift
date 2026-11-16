// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct MacPairApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("MacPair", id: "compact-main") { MainView(model: model) }
            .defaultSize(width: 720, height: 550)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showsSettings = false
    @State private var diagnosticsExpanded: Bool

    init(model: AppModel, diagnosticsExpanded: Bool = false) {
        self.model = model
        _diagnosticsExpanded = State(initialValue: diagnosticsExpanded)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "display.2").font(.system(size: 28)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text("MacPair").font(.title2.bold())
                            Text(L("Prototype 0.1.7")).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(L("Your nearby Mac. Your second display.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showsSettings.toggle() } label: {
                        Image(systemName: "gearshape").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Settings"))
                    .accessibilityLabel(L("Settings"))
                    .popover(isPresented: $showsSettings) { settingsPanel }
                }
                Picker(L("This Mac's role"), selection: $model.role) {
                    ForEach(MacRole.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.occupied || model.listening)
                .onChange(of: model.role) { _ in model.stopAll() }

                if model.role == .receiver { receiverPanel } else { hostPanel }
                statusPanel
                if model.connected {
                    HStack {
                        Button(L("Disconnect")) { model.endSession() }
                        if model.role == .receiver, !model.diagnostic {
                            Button(L("Open display")) { model.showViewer() }
                            Button(L("Full screen")) { model.showViewer(fullscreen: true) }
                        }
                        if model.role == .host, model.isExtending {
                            Button(L("Arrange displays")) { model.openDisplays() }
                        }
                    }
                }
                if model.connected, !model.rememberedSession {
                    Text(L("This session could not be remembered. Allow Keychain access and pair again to skip codes next time."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(L("Diagnostics"), isExpanded: $diagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.path.localized).font(.caption.monospaced())
                        if model.connected {
                            Text(L("Round trip \(model.rtt)")).font(.caption.monospaced())
                            Text(L("\(model.fps) fps · \(model.totalFrames) frames")).font(.caption.monospaced())
                        }
                        if model.role == .host {
                            HStack {
                                Button(L("Test connection")) { model.connect(testOnly: true) }
                                    .disabled(model.occupied || model.selectedPeer?.isDirect != true)
                                Text(L("Checks the link without sharing a screen.")).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                        ForEach(Array(model.events.enumerated()), id: \.offset) { _, text in
                            Text(text.localized).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Button(L("Copy diagnostics")) { model.copyDiagnostics() }.padding(.top, 4)
                    }.padding(.top, 7).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(L("Keep Wi-Fi on on both Macs.")).font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(minWidth: 660, minHeight: 510)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Settings")).font(.headline)
            Picker(L("Language"), selection: $model.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Text(L("Paired Macs")).font(.headline)
            if model.trustedDevices.isEmpty {
                Text(L("No saved pairings yet.")).font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.trustedDevices) { device in
                            HStack {
                                Label(device.peer.name, systemImage: "laptopcomputer").lineLimit(1)
                                Spacer()
                                Button(L("Forget")) { model.forgetDevice(device) }.disabled(model.occupied)
                            }
                        }
                    }
                }.frame(maxHeight: 150)
            }
            Text(L("Pair once with six digits. Remembered Macs need no code."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 340)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(model.connectionTitle.localized, systemImage: model.connected ? "checkmark.circle.fill" : "circle")
                    .font(.headline).foregroundStyle(model.connected ? .green : .primary)
                Spacer()
                if model.connected {
                    if !model.diagnostic { Text(L("\(model.fps) fps")) }
                    if model.rtt != "—" { Text(L("Round trip \(model.rtt)")) }
                }
            }
            if model.status.localized != model.connectionTitle.localized {
                Text(model.status.localized).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !model.occupied, let previous = model.lastSession {
                HStack(spacing: 10) {
                    Text(L("Last session"))
                    if previous.diagnostic { Text(L("Connection test")) }
                    if previous.rtt != "—" { Text(L("Round trip \(previous.rtt)")) }
                    if !previous.diagnostic { Text(L("\(previous.frames) frames")) }
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 3)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }

    private var hostPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L("Display mode")).font(.callout)
                Picker(L("Display mode"), selection: $model.displayMode) {
                    ForEach(DisplayMode.allCases) { Text(L10n.text($0.title)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 115).disabled(model.occupied)
                if model.displayMode == .extend {
                    Text(L("Resolution")).font(.callout).padding(.leading, 10)
                    Picker(L("Display resolution"), selection: $model.resolution) {
                        ForEach(ResolutionPreset.allCases) { Text(L10n.text($0.title)).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 205).disabled(model.occupied)
                    .help(L("Default matches the display Mac. Larger Text increases text size; More Space fits more windows. Reconnect to change."))
                }
                Spacer(minLength: 0)
            }
            Text(L(model.displayMode == .mirror
                ? "Mirror shows the host's main screen on the display Mac."
                : "Extend adds a separate desktop; drag windows onto it."))
                .font(.caption).foregroundStyle(.secondary)
            if !model.connected {
                HStack {
                    Text(L("Nearby displays")).font(.headline)
                    Spacer()
                    Button(L(model.browsing ? "Search again" : "Find nearby displays")) { model.browse() }
                        .disabled(model.occupied)
                }
                if model.peers.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        if model.browsing { SearchingText(text: L("Looking for displays…")) }
                        Text(L("On the other Mac, choose Display Mac → Wait for connection."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(model.peers) { peer in
                                Button { model.selectedID = peer.id } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: model.selectedID == peer.id ? "largecircle.fill.circle" : "circle")
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(peer.name).lineLimit(1)
                                                if model.isTrusted(peer) {
                                                    Image(systemName: "lock.fill").foregroundStyle(.blue)
                                                        .accessibilityLabel(L("Paired · No code needed"))
                                                }
                                            }
                                            Text(L(peer.isDirect ? "Ready to connect" : "Waiting for direct Wi-Fi…"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if peer.isDirect { Image(systemName: "wifi").foregroundStyle(.green) }
                                    }.padding(7).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(model.occupied || !peer.isDirect)
                                .background(model.selectedID == peer.id ? .blue.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }.frame(height: 76)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if model.selectedPeerIsTrusted {
                            Label(L("Paired · No code needed"), systemImage: "lock.fill").font(.callout)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        } else {
                            Text(L("Pairing code")).font(.caption).foregroundStyle(.secondary)
                            TextField(L("Six digits from the display Mac"), text: $model.enteredCode)
                                .textFieldStyle(.roundedBorder).disabled(model.occupied)
                        }
                    }
                    Button(L(model.connecting ? "Connecting…" : "Connect")) { model.connect(testOnly: false) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(model.occupied || model.selectedPeer?.isDirect != true)
                        .frame(minWidth: 90)
                }
                if !model.permission {
                    HStack {
                        Text(L("Screen Recording is required on the host.")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Grant Screen Recording")) { model.requestPermission() }.controlSize(.small)
                    }
                }
            }
        }
    }

    private var receiverPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.occupied && model.pairingCode.isEmpty {
                Text(L("Paired. A new code will appear after disconnecting."))
                    .font(.callout).foregroundStyle(.secondary)
            } else if model.listening {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Pairing code")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if model.pairingCode.isEmpty {
                            Label(L("Paired Macs only"), systemImage: "lock.fill").font(.callout)
                        } else {
                            Text(model.pairingCode).font(.system(size: 32, weight: .semibold, design: .monospaced)).tracking(4)
                                .textSelection(.enabled).accessibilityLabel(L("Pairing code"))
                        }
                        Spacer()
                        Button(L("New code")) { model.newPairingCode() }.disabled(model.occupied)
                        Button(L("Stop waiting")) { model.stopAll() }.disabled(model.cleaning)
                    }
                    Text(L(model.pairingCode.isEmpty
                        ? "Paired Macs can connect without a code. Choose New code to pair a new Mac."
                        : "Valid for 5 minutes. Enter it on the host for first pairing only."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(14).background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            } else {
                Button(L("Wait for connection")) { model.listen() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.occupied || model.pairingCoolingDown)
            }
            Text(L("Connect on the host to open this display in full screen. Press Esc to exit."))
                .font(.callout).foregroundStyle(.secondary)
            Text(L("Use the host's keyboard and trackpad. Display-side input and audio are not included yet."))
                .font(.caption).foregroundStyle(.secondary)
        }
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
