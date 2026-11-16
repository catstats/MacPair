// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Network
import AVFoundation
import CoreGraphics

enum MacRole: String, CaseIterable { case host = "Host Mac", receiver = "Display Mac" }

@MainActor
final class AppModel: NSObject, ObservableObject, NSWindowDelegate {
    @Published var language = L10n.language {
        didSet {
            L10n.setLanguage(language)
            viewerWindow?.title = L("MacPair Display · Double-click to toggle full screen")
            updateViewerHUD()
        }
    }
    @Published var role: MacRole = .host
    @Published var displayMode: DisplayMode = .extend
    @Published var resolution: ResolutionPreset = .recommended
    @Published var peers: [DiscoveredPeer] = []
    @Published var selectedID: String?
    @Published var enteredCode = ""
    @Published var pairingCode = ""
    @Published var pairingCoolingDown = false
    @Published var trustedDevices: [TrustedDeviceSummary] = []
    @Published var rememberedSession = false
    @Published var status: LocalizedMessage = "Place both Macs nearby. Select Display Mac on the other Mac."
    @Published var path: LocalizedMessage = "Not connected"
    @Published var rtt = "—"
    @Published var fps = 0
    @Published var totalFrames = 0
    @Published var browsing = false
    @Published var listening = false
    @Published var connected = false
    @Published var connecting = false
    @Published var cleaning = false
    @Published var permission = CGPreflightScreenCaptureAccess()
    @Published var events: [LocalizedMessage] = []
    @Published var diagnostic = false

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var link: PeerLink?
    private var activeHello: SessionHello?
    private var requestedHello: SessionHello?
    private var mirrorDisplayID: CGDirectDisplayID?
    private var screen: VirtualScreen?
    private var streamer: ScreenStreamer?
    private var setupTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var statsTimer: Timer?
    private var framesThisSecond = 0
    private let samples = H264Samples()
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var viewerWindow: NSWindow?
    private var viewerEnteredFullScreen = false
    private var viewerFullScreenFailed = false
    private var receivedWidth = 0
    private var receivedHeight = 0
    private var helloDeadline: DispatchWorkItem?
    private var pairingExpiry: Task<Void, Never>?
    private var pairingCooldown: Task<Void, Never>?
    private var pairingGate = PairingGate()
    private var wantsToListen = false
    private var sessionAuthenticated = false
    private let trustStore: TrustStore
    let localIdentity: PeerIdentity
    private var previousCode: String?
    private var pendingTrust: TrustedDevice?
    private var pendingTrustIsNew = false
    private var localTrustSaved = false
    private var receivedTrustStatus = false
    private var trustConfirmed = false
    private let serviceName = "MacPair · " + (Host.current().localizedName ?? "Mac")
    var selectedPeer: DiscoveredPeer? { peers.first { $0.id == selectedID } }
    var occupied: Bool { connected || connecting || cleaning }
    var isExtending: Bool { activeHello?.mode == "extend" }

    init(trustStore: TrustStore = TrustStore(), identity: PeerIdentity? = nil) {
        self.trustStore = trustStore
        self.localIdentity = identity ?? PeerIdentity.local()
        super.init()
        reloadTrustedDevices()
    }
    var receivingPort: NWEndpoint.Port? { listener?.port }
    var selectedPeerIsTrusted: Bool { selectedPeer.map(isTrusted) ?? false }
    func isTrusted(_ peer: DiscoveredPeer) -> Bool {
        guard let id = peer.deviceIdentity?.id else { return false }
        return trustedDevices.contains { $0.peer.id == id }
    }
    private func reloadTrustedDevices() {
        do {
            var newest: [String: TrustedDevice] = [:]
            for record in try trustStore.all() {
                if newest[record.peer.id].map({ $0.createdAt >= record.createdAt }) != true { newest[record.peer.id] = record }
            }
            trustedDevices = newest.values.map(\.summary).sorted { $0.peer.name < $1.peer.name }
        } catch { log(error.appMessage) }
    }
    func forgetDevice(_ device: TrustedDeviceSummary) {
        guard !occupied else { return }
        do {
            try trustStore.forgetPeer(device.peer.id)
            enteredCode = ""
            reloadTrustedDevices()
            status = "Forgot \(device.peer.name). Use a new six-digit code to pair again."
        } catch { status = error.appMessage }
    }
    func forgetSelectedDevice() {
        guard let id = selectedPeer?.deviceIdentity?.id,
              let device = trustedDevices.first(where: { $0.peer.id == id }) else { return }
        forgetDevice(device)
    }
    func log(_ text: LocalizedMessage) {
        events.append(text)
        if events.count > 12 { events.removeFirst(events.count - 12) }
    }
    func browse() {
        guard !occupied else { return }
        browser?.cancel()
        peers = []
        selectedID = nil
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: PeerNetwork.serviceType, domain: nil),
                                using: PeerNetwork.discoveryParameters())
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            DispatchQueue.main.async {
                guard let self, let browser, self.browser === browser else { return }
                switch state {
                case .ready:
                    self.browsing = true
                    self.status = "Looking for nearby displays… Keep Wi-Fi on on both Macs."
                case .failed(let error):
                    self.browsing = false
                    self.status = "Discovery failed: \(error.localizedDescription). Check Local Network permission."
                case .waiting(let error):
                    self.status = "Waiting for network: \(error.localizedDescription)"
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            DispatchQueue.main.async {
                guard let self, let browser, self.browser === browser else { return }
                self.peers = results.compactMap(DiscoveredPeer.init).sorted { $0.name < $1.name }
                if !self.peers.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = self.peers.first(where: \.isDirect)?.id
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }
    func listen() {
        guard !occupied, !listening else { return }
        guard pairingGate.issue(at: PairingTime.now) else {
            status = "Pairing is temporarily paused. Please wait before trying again."
            return
        }
        wantsToListen = true
        pairingCode = PairingCode.generate(excluding: previousCode)
        previousCode = pairingCode
        do {
            let listener = try NWListener(using: PeerNetwork.parameters())
            listener.service = NWListener.Service(name: serviceName, type: PeerNetwork.serviceType,
                txtRecord: NWTXTRecord(["id": localIdentity.id, "pairing": "3"]))
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                DispatchQueue.main.async {
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready:
                        self.listening = true
                        self.status = "Waiting for the host. Select this Mac on the host and enter the pairing code below."
                        self.log("Display advertising via Bonjour with peer-to-peer Wi-Fi enabled")
                    case .failed(let error):
                        self.stopAll(reason: "Listener failed: \(error.localizedDescription)")
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                DispatchQueue.main.async {
                    guard let self, let listener, self.listener === listener,
                          self.link == nil, !self.cleaning else { connection.cancel(); return }
                    guard !self.pairingGate.isLocked(at: PairingTime.now) else {
                        connection.cancel(); return
                    }
                    let activeCode = self.pairingGate.accepts(at: PairingTime.now) ? self.pairingCode : nil
                    self.connecting = true
                    self.sessionAuthenticated = false
                    self.status = "Verifying pairing…"
                    let store = self.trustStore
                    self.attach(PeerLink(connection, host: false, code: activeCode, identity: self.localIdentity,
                        lookupTrusted: { try store.credential(id: $0) }))
                }
            }
            self.listener = listener
            listener.start(queue: .main)
            pairingExpiry?.cancel()
            pairingExpiry = Task { @MainActor [weak self, weak listener] in
                do { try await Task.sleep(for: .seconds(PairingGate.lifetime), clock: .continuous) }
                catch { return }
                guard let self, let listener, self.listener === listener, !self.sessionAuthenticated else { return }
                self.expirePairingCode()
            }
        } catch {
            wantsToListen = false
            pairingCode = ""
            pairingGate.invalidate()
            status = error.appMessage
        }
    }
    // Expiry closes the short-code invitation, while already trusted Macs
    // remain reachable without a new code.
    func expirePairingCode() {
        pairingGate.invalidate()
        pairingCode = ""
        pairingExpiry?.cancel(); pairingExpiry = nil
        status = "Code expired. Paired Macs can still connect. Choose New code to pair another Mac."
    }
    private func stopAdvertising() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil; listening = false
    }
    func newPairingCode() {
        guard !occupied, listening, !pairingCoolingDown else { return }
        pairingExpiry?.cancel()
        stopAdvertising()
        listen()
    }
    private func failedPairing() -> Bool {
        guard pairingGate.failed(at: PairingTime.now) else { return false }
        wantsToListen = false
        pairingCode = ""
        pairingExpiry?.cancel()
        stopAdvertising()
        pairingCoolingDown = true
        pairingCooldown?.cancel()
        pairingCooldown = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(PairingGate.cooldown), clock: .continuous) }
            catch { return }
            guard let self else { return }
            self.pairingCoolingDown = false
            if self.role == .receiver, !self.occupied, !self.listening {
                self.status = "Ready for a new code. Click Wait for connection."
            }
        }
        return true
    }
    func connect(testOnly: Bool) {
        guard !occupied, let peer = selectedPeer, let interface = peer.directInterface else {
            status = "Select a display with a direct AWDL interface."
            return
        }
        guard let peerIdentity = peer.deviceIdentity else {
            status = "Waiting for the display's identity. Search again and use the latest MacPair on both Macs."
            return
        }
        let trusted: TrustedDevice?
        do { trusted = try trustStore.credential(forPeer: peerIdentity.id); reloadTrustedDevices() }
        catch { status = error.appMessage; return }
        let code = PeerNetwork.normalize(enteredCode)
        guard trusted != nil || PairingCode.isValid(code) else {
            status = "Enter the six-digit code shown on the display Mac."
            return
        }
        permission = CGPreflightScreenCaptureAccess()
        guard testOnly || permission else {
            status = "The host needs Screen Recording permission. Click Grant Screen Recording, allow access, then quit and reopen the app."
            return
        }
        diagnostic = testOnly
        do {
            var width = 1280
            var height = 800
            mirrorDisplayID = nil
            if !testOnly, displayMode == .mirror {
                let id = CGMainDisplayID()
                let size = try MirrorSizing.dimensions(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id))
                mirrorDisplayID = id
                width = size.width
                height = size.height
            }
            requestedHello = SessionHello(version: Wire.version,
                mode: testOnly ? "diagnostic" : displayMode.rawValue, width: width, height: height, fps: 30,
                resolution: !testOnly && displayMode == .extend ? resolution : .recommended)
            try requestedHello?.validateRequest()
        } catch { status = error.appMessage; return }
        connecting = true
        status = "Establishing an encrypted connection over \(interface.name)…"
        log("Connection restricted to \(interface.name); router-network fallback is disabled")
        let connection = NWConnection(to: peer.endpoint,
            using: PeerNetwork.parameters(interface: interface))
        attach(PeerLink(connection, host: true, code: trusted == nil ? code : nil, identity: localIdentity,
            expectedPeer: peerIdentity, trusted: trusted))
    }
    private func attach(_ link: PeerLink) {
        self.link = link
        sessionID = UUID()
        let token = sessionID
        link.onPath = { [weak self, weak link] text in
            guard let self, let link, self.link === link else { return }
            self.path = text
        }
        link.onRTT = { [weak self, weak link] ms in
            guard let self, let link, self.link === link else { return }
            self.rtt = String(format: "%.1f ms", ms)
        }
        link.onClosed = { [weak self, weak link] reason in
            guard let self, let link, self.link === link else { return }
            let limited = self.role == .receiver && self.wantsToListen && !self.sessionAuthenticated
                ? self.failedPairing() : false
            let reconnectFailed = self.role == .host && link.isResuming && !self.sessionAuthenticated
            self.endSession(reason: limited
                ? "Pairing paused after 5 failed attempts. Wait 30 seconds, then start waiting again."
                : reconnectFailed ? "Could not verify the saved pairing. Check Wi-Fi and the other Mac; if needed, forget this Mac and pair again."
                : reason)
        }
        link.onReady = { [weak self, weak link] in
            guard let self, let link, self.link === link else { return }
            self.log("Secure pairing verified · SPAKE2 + AES-256-GCM")
            self.sessionAuthenticated = true
            self.enteredCode = ""
            if self.role == .receiver {
                self.pairingGate.consume()
                self.pairingCode = ""
                self.pairingExpiry?.cancel()
                self.pairingExpiry = nil
                self.stopAdvertising()
            }
            guard let credential = link.authenticatedCredential else {
                self.endSession(reason: "Invalid saved pairing"); return
            }
            self.pendingTrust = credential
            self.pendingTrustIsNew = !link.isResuming
            do {
                if !link.isResuming { try self.trustStore.save(credential) }
                self.localTrustSaved = true
            } catch {
                self.localTrustSaved = false
                self.log(error.appMessage)
            }
            // Wait for both encrypted acknowledgements before advertising a
            // remembered pairing or starting the display-session handshake.
            link.send(.trustStatus, Data([self.localTrustSaved ? 1 : 0]))
        }
        link.onPacket = { [weak self, weak link] packet in
            guard let self, let link, self.link === link else { return }
            do { try self.handle(packet, link: link, token: token) }
            catch {
                link.send(.failure, Data(error.localizedDescription.utf8))
                self.endSession(reason: error.appMessage)
            }
        }
        let deadline = DispatchWorkItem { [weak self, weak link] in
            guard let self, let link, self.link === link, !self.connected else { return }
            self.endSession(reason: "Session handshake timed out")
        }
        helloDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: deadline)
        link.start()
    }
    private func handle(_ packet: Packet, link: PeerLink, token: UUID) throws {
        switch packet.kind {
        case .trustStatus:
            guard sessionAuthenticated, !receivedTrustStatus, activeHello == nil,
                  packet.body.count == 1, let value = packet.body.first, value <= 1 else {
                throw PairError.message("Invalid session sequence")
            }
            receivedTrustStatus = true
            let peerSaved = value == 1
            if let pendingTrust, pendingTrustIsNew, localTrustSaved {
                if peerSaved {
                    try trustStore.forgetPeer(pendingTrust.peer.id, keeping: pendingTrust.id)
                } else {
                    try trustStore.forget(id: pendingTrust.id)
                    localTrustSaved = false
                }
            }
            rememberedSession = localTrustSaved && peerSaved
            trustConfirmed = rememberedSession
            reloadTrustedDevices()
            log(rememberedSession ? "This Mac is remembered. Future connections need no code."
                : "Connected for this session only. Pair again after allowing Keychain access to remember this Mac.")
            if role == .host, let requestedHello {
                link.send(.hello, try JSONEncoder().encode(requestedHello))
            }
        case .hello:
            guard role == .receiver, receivedTrustStatus, activeHello == nil else { throw PairError.message("Invalid session sequence") }
            let hello = try JSONDecoder().decode(SessionHello.self, from: packet.body)
            try hello.validateRequest()
            activeHello = hello // Reserve this handshake while full screen settles.
            diagnostic = hello.mode == "diagnostic"
            if diagnostic {
                link.send(.ready, try JSONEncoder().encode(hello))
                sessionReady()
                status = "Connection test passed. Disconnect on the host, choose Mirror or Extend, then start streaming."
            } else {
                prepareReceiver(link: link, request: hello, token: token)
            }
        case .ready:
            guard role == .host, receivedTrustStatus, activeHello == nil, let requestedHello else {
                throw PairError.message("Invalid session sequence")
            }
            let hello = try JSONDecoder().decode(SessionHello.self, from: packet.body)
            try hello.validateResponse(to: requestedHello)
            activeHello = hello
            logDimensions(hello)
            sessionReady()
            if diagnostic { status = "AWDL connection test passed. Round-trip time is shown below."; log("Peer-to-peer session handshake completed") }
            else { beginStreaming(link: link, hello: hello, token: token) }
        case .format:
            guard role == .receiver, connected, let hello = activeHello, hello.isVideo else {
                throw PairError.message("Video session has not been negotiated")
            }
            try samples.configure(packet.body, expectedWidth: hello.width, expectedHeight: hello.height)
            if let format = samples.format {
                let size = CMVideoFormatDescriptionGetDimensions(format)
                receivedWidth = Int(size.width); receivedHeight = Int(size.height)
                updateViewerHUD()
            }
        case .video:
            guard role == .receiver, connected, activeHello?.isVideo == true else {
                throw PairError.message("Video session has not been negotiated")
            }
            let sample = try samples.sample(packet.body)
            if displayLayer.status == .failed {
                throw PairError.message("Video display failed: \(displayLayer.error?.localizedDescription ?? "unknown error")")
            }
            displayLayer.enqueue(sample)
            countFrame()
            if totalFrames == 1 {
                status = activeHello?.mode == "mirror"
                    ? "Receiving the mirrored screen. Double-click the video to toggle full screen."
                    : "Receiving the extended desktop. Double-click the video to toggle full screen."
                log("First H.264 frame received")
            }
        case .failure:
            throw PairError.message("Peer reported: \(String(decoding: packet.body.prefix(512), as: UTF8.self))")
        case .ping, .pong: break // Handled by the transport.
        case .pairOffer, .pairProof, .sealed:
            throw PairError.message("Invalid session sequence")
        }
    }
    private func prepareReceiver(link: PeerLink, request: SessionHello, token: UUID) {
        status = "Matching the display Mac's resolution…"
        setupTask = Task { [weak self, weak link] in
            guard let self, let link else { return }
            do {
                let info = try await self.prepareViewer()
                guard self.sessionID == token else { return }
                let hello = try request.negotiated(for: info)
                self.activeHello = hello
                self.logDimensions(hello)
                link.send(.ready, try JSONEncoder().encode(hello))
                self.sessionReady()
                self.updateViewerHUD()
                self.status = hello.mode == "mirror" ? "Connected. Waiting for the mirrored screen…" : "Connected. Waiting for the extended desktop…"
            } catch {
                guard self.sessionID == token else { return }
                link.send(.failure, Data(error.localizedDescription.utf8))
                self.endSession(reason: error.appMessage)
            }
        }
    }
    func prepareViewer() async throws -> ReceiverDisplayInfo {
        showViewer(fullscreen: true)
        // Wait for AppKit's completion notification, not the style bit that
        // changes at the start of the full-screen animation.
        for _ in 0..<70 {
            try Task.checkCancellation()
            if viewerEnteredFullScreen || viewerFullScreenFailed { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try Task.checkCancellation()
        guard viewerEnteredFullScreen, let view = viewerWindow?.contentView as? NativeVideoView else {
            throw PairError.message("Cannot enter full screen on the display Mac. Close other full-screen windows and reconnect.")
        }
        view.layoutSubtreeIfNeeded()
        return try view.displayInfo()
    }
    private func logDimensions(_ hello: SessionHello) {
        guard let info = hello.receiver else { return }
        let s = info.screen, v = info.viewport
        log("Receiver \(info.name): \(s.logicalWidth) × \(s.logicalHeight) pt, \(s.backingWidth) × \(s.backingHeight) px, \(s.scale)×")
        log("Full-screen viewport: \(v.logicalWidth) × \(v.logicalHeight) pt, \(v.backingWidth) × \(v.backingHeight) px")
        if let canvas = hello.canvas {
            log("Desktop: \(canvas.width) × \(canvas.height) pt at \(canvas.scale)×; stream: \(hello.width) × \(hello.height) px")
        }
    }
    private func updateViewerHUD() {
        guard let view = viewerWindow?.contentView as? NativeVideoView, let hello = activeHello else { return }
        let stream: LocalizedMessage = receivedWidth > 0
            ? "Stream \(receivedWidth) × \(receivedHeight) px · \(fps) fps"
            : "Waiting for video…"
        if let canvas = hello.canvas {
            view.setHUD(L("Desktop \(canvas.width) × \(canvas.height) pt · \(canvas.scale)×") + "\n" + stream.localized)
        } else { view.setHUD(L10n.text("Mirror") + "\n" + stream.localized) }
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === viewerWindow else { return }
        viewerEnteredFullScreen = true
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === viewerWindow else { return }
        viewerEnteredFullScreen = false
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        guard window === viewerWindow else { return }
        viewerFullScreenFailed = true
    }
    private func sessionReady() {
        helloDeadline?.cancel()
        connecting = false
        connected = true
        totalFrames = 0
        framesThisSecond = 0
        statsTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.connected else { return }
                self.fps = self.framesThisSecond
                self.framesThisSecond = 0
                self.updateViewerHUD()
            }
        }
        statsTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func beginStreaming(link: PeerLink, hello: SessionHello, token: UUID) {
        status = hello.mode == "mirror" ? "Preparing the host's main screen for mirroring…" : "Creating a Retina-aware extended desktop…"
        let mirrorSourceID = mirrorDisplayID
        setupTask = Task { [weak self, weak link] in
            guard let self, let link else { return }
            do {
                let captureID: CGDirectDisplayID
                if hello.mode == "extend" {
                    guard let canvas = hello.canvas else { throw PairError.message("The display returned incompatible parameters") }
                    let screen = try VirtualScreen(width: canvas.width, height: canvas.height, scale: canvas.scale)
                    screen.onError = { [weak self] message in
                        guard let self, self.sessionID == token else { return }
                        self.endSession(reason: message)
                    }
                    self.screen = screen
                    try await screen.arrange()
                    captureID = screen.id
                } else if hello.mode == "mirror", let mirrorSourceID, VirtualScreen.isOnline(mirrorSourceID) {
                    // Mirror the existing main display. Do not create or rearrange
                    // any virtual screen in this mode.
                    captureID = mirrorSourceID
                } else {
                    throw PairError.message("The main display is no longer available for mirroring")
                }
                try Task.checkCancellation()
                guard self.sessionID == token else { return }
                let streamer = try ScreenStreamer(link: link, width: hello.width, height: hello.height, fps: hello.fps)
                self.streamer = streamer
                streamer.onError = { [weak self] text in
                    DispatchQueue.main.async {
                        guard let self, self.sessionID == token else { return }
                        self.endSession(reason: "Screen streaming failed: \(text)")
                    }
                }
                streamer.onCaptureInfo = { [weak self] message in
                    DispatchQueue.main.async {
                        guard let self, self.sessionID == token else { return }
                        self.log(message)
                    }
                }
                streamer.onSent = { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, self.sessionID == token else { return }
                        self.countFrame()
                    }
                }
                try await streamer.start(displayID: captureID, width: hello.width, height: hello.height, fps: hello.fps)
                if Task.isCancelled || self.sessionID != token { await streamer.stop(); return }
                if hello.mode == "mirror" {
                    self.status = "Mirroring the host's main screen. Open or move a window to check the other Mac."
                    self.log("Mirror source \(captureID): \(hello.width) × \(hello.height), H.264 up to \(hello.fps) fps")
                } else {
                    self.status = "Extended desktop is ready. Drag a window past the host desktop's right edge."
                    self.log("Virtual display \(captureID): \(hello.width) × \(hello.height) pixels, H.264 up to \(hello.fps) fps")
                }
            } catch {
                if self.sessionID == token { self.endSession(reason: error.appMessage) }
            }
        }
    }
    private func countFrame() { totalFrames += 1; framesThisSecond += 1 }
    func endSession(reason: LocalizedMessage = "Connection ended") {
        if pendingTrustIsNew, !trustConfirmed, localTrustSaved, let pendingTrust {
            do { try trustStore.forget(id: pendingTrust.id) } catch { log(error.appMessage) }
        }
        pendingTrust = nil
        pendingTrustIsNew = false
        localTrustSaved = false
        receivedTrustStatus = false
        trustConfirmed = false
        rememberedSession = false
        sessionID = UUID()
        helloDeadline?.cancel()
        helloDeadline = nil
        link?.onClosed = nil
        link?.cancel()
        link = nil
        statsTimer?.invalidate()
        statsTimer = nil
        connected = false
        connecting = false
        fps = 0
        activeHello = nil
        requestedHello = nil
        mirrorDisplayID = nil
        sessionAuthenticated = false
        receivedWidth = 0; receivedHeight = 0
        displayLayer.flushAndRemoveImage()
        samples.reset()
        viewerWindow?.delegate = nil
        viewerWindow?.close()
        viewerWindow = nil
        viewerEnteredFullScreen = false
        viewerFullScreenFailed = false
        let oldTask = setupTask
        let oldStreamer = streamer
        let oldScreen = screen
        setupTask = nil
        streamer = nil
        screen = nil
        oldTask?.cancel()
        cleaning = true
        status = "Ending session…"
        Task {
            await oldTask?.value
            await oldStreamer?.stop()
            // Keep the screen alive until its capture is fully stopped. Releasing
            // it removes the virtual monitor and macOS brings its windows back.
            oldScreen?.close()
            self.cleaning = false
            if self.role == .receiver, self.wantsToListen, self.listener == nil {
                self.listen() // A successfully used code is replaced before reconnecting.
            } else {
                self.status = self.listening ? "\(reason) Waiting for the host to reconnect." : reason
            }
            self.log(reason)
        }
    }
    func stopAll(reason: LocalizedMessage = "Stopped") {
        browser?.cancel(); browser = nil; browsing = false
        wantsToListen = false
        pairingGate.invalidate()
        pairingCode = ""
        pairingExpiry?.cancel(); pairingExpiry = nil
        stopAdvertising()
        peers = []; selectedID = nil
        endSession(reason: reason)
    }
    func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        permission = CGPreflightScreenCaptureAccess()
        if !permission {
            openPrivacySettings()
            status = "Allow MacPair in System Settings, then quit and reopen this app."
        }
    }
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    func openDisplays() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    func showViewer(fullscreen: Bool = false) {
        if viewerWindow == nil {
            displayLayer.videoGravity = .resizeAspect
            let targetScreen = NSApp.keyWindow?.screen ?? NSScreen.main
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false, screen: targetScreen)
            window.title = L("MacPair Display · Double-click to toggle full screen")
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            window.contentView = NativeVideoView(videoLayer: displayLayer)
            window.center()
            viewerWindow = window
            viewerEnteredFullScreen = false
            viewerFullScreenFailed = false
        }
        viewerWindow?.makeKeyAndOrderFront(nil)
        if fullscreen { NSApp.activate(ignoringOtherApps: true) }
        if fullscreen, viewerWindow?.styleMask.contains(.fullScreen) == false {
            viewerFullScreenFailed = false
            viewerWindow?.toggleFullScreen(nil)
        }
        updateViewerHUD()
    }
    func copyDiagnostics() {
        let text = (["MacPair 0.1.6", ProcessInfo.processInfo.operatingSystemVersionString,
                     L10n.text(role.rawValue), status.localized, path.localized, "RTT \(rtt), frames \(totalFrames), fps \(fps)"] + events.map(\.localized)).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

final class NativeVideoView: NSView {
    private let videoLayer: AVSampleBufferDisplayLayer
    private let hud = NSTextField(wrappingLabelWithString: "")
    private let hudBackground = NSVisualEffectView()
    init(videoLayer: AVSampleBufferDisplayLayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)
        hudBackground.material = .hudWindow
        hudBackground.appearance = NSAppearance(named: .vibrantDark)
        hudBackground.blendingMode = .withinWindow
        hudBackground.state = .active
        hudBackground.wantsLayer = true
        hudBackground.layer?.cornerRadius = 7
        hudBackground.layer?.masksToBounds = true
        hud.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hud.textColor = .white
        hud.isSelectable = false
        hudBackground.addSubview(hud)
        addSubview(hudBackground)
        hudBackground.isHidden = true
    }
    func setHUD(_ text: String) {
        hud.stringValue = text
        hudBackground.isHidden = text.isEmpty
        needsLayout = true
    }
    func displayInfo() throws -> ReceiverDisplayInfo {
        guard let screen = window?.screen else {
            throw PairError.message("Cannot read the display Mac's screen settings")
        }
        func geometry(_ logical: NSSize, _ backing: NSSize) -> DisplayGeometry {
            DisplayGeometry(logicalWidth: Int(logical.width.rounded()), logicalHeight: Int(logical.height.rounded()),
                backingWidth: Int(backing.width.rounded()), backingHeight: Int(backing.height.rounded()),
                scale: Int(screen.backingScaleFactor.rounded()))
        }
        let info = ReceiverDisplayInfo(name: String(screen.localizedName.prefix(80)),
            screen: geometry(screen.frame.size, screen.convertRectToBacking(screen.frame).size),
            viewport: geometry(bounds.size, convertToBacking(bounds).size))
        try info.validate()
        return info
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
        let size = hud.sizeThatFits(NSSize(width: max(0, bounds.width - 56), height: 70))
        hudBackground.frame = NSRect(x: 16, y: 16, width: size.width + 20, height: size.height + 14)
        hud.frame = NSRect(x: 10, y: 7, width: size.width, height: size.height)
    }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.toggleFullScreen(nil) }
    }
    override func cancelOperation(_ sender: Any?) {
        if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
    }
}
