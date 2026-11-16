# MacPair

Extend your desktop onto a nearby Mac, or mirror your main screen. The user has confirmed that the two-Mac display works when the Macs are connected to different Wi-Fi networks.

**Prototype 0.1.6. English is the default; switch to 简体中文 from the language menu.** [中文说明](README.zh-CN.md)

The local protocol, secure-pairing, H.264, and virtual-display checks have passed on the development Mac. **User report on 2026-11-16: virtual display and operation across different Wi-Fi networks passed. The user-described “no Wi-Fi” scenario did not work; whether the Wi-Fi radio was off or merely disconnected was not specified.** Standalone operation without an access point remains unconfirmed. See [test instructions and verification record](TESTING.md).

## Start here

Double-click `Start MacPair.command`. In an iCloud checkout the runnable App is kept in this Mac's local cache; the launcher finds it automatically. Outside iCloud, the default App path is `build/MacPair.app`.

To use a second Mac, copy `build/MacPair-0.1.6.zip` to it, unzip it, and open MacPair.app. The package includes the full source. The second Mac does not need Xcode.

Requirements: macOS 13 or later on both Macs, with compatible Apple peer-to-peer Wi-Fi hardware. The app is a universal arm64/x86_64 build. Both architectures have been compiled; the processor and OS versions of the user-tested pair were not separately recorded.

This local build is ad hoc signed and is not notarized by Apple. If macOS blocks it, use the app-specific approval in **System Settings → Privacy & Security → Open Anyway** for your own build. You do not need to disable SIP or global Gatekeeper.

## Test the direct connection first

1. Put both Macs nearby. **Keep Wi-Fi switched on.** Bluetooth is recommended.
2. On the display Mac, choose **Display Mac → Wait for connection**.
3. Allow **Local Network** access if macOS asks. Allow the app's incoming connection if the firewall asks.
4. On the host Mac, choose **Host Mac → Find nearby displays**.
5. Select the other Mac when it shows **Direct AWDL available**.
6. First pairing: enter the **six-digit number** shown on the display Mac. Click **Test connection**. Previously paired Macs show **Paired · No code needed** and skip this input.
7. The host should show **AWDL connection test passed**, with a round-trip time.

This test requires no Screen Recording permission and creates no virtual screen.

## Pair once; reconnect without typing

Both Macs need **0.1.6**. The new pairing transport uses protocol v3 and its own Bonjour service, so older builds do not appear as compatible peers.

- A new Mac uses a uniformly random **six-digit numeric code**, including possible leading zeroes. It expires after **5 minutes** and is invalidated on successful authentication. Spaces or a hyphen are accepted when pasting.
- After both Macs confirm the saved pairing, the app stores a **strong per-device credential in the local macOS login Keychain**. It never saves the six-digit code. The app does not synchronize these credentials through iCloud.
- Next time, open the apps, keep the display Mac waiting, select it on the host, and click Test connection, Mirror or Extend. **No code is needed for a remembered Mac.** This also works after reopening the app, and when reversing the Macs' roles. It is a manual connection, not automatic sleep/reconnect recovery.
- Expiring a short code leaves remembered Macs available. Choose **New code** only when adding a new Mac.
- **Paired Macs → Forget**, available on either Mac while disconnected, removes its credential. The other Mac may also need to forget its stale saved entry before pairing again with a new code. A matching computer name alone never grants trust.
- Five failed pairing attempts share one global budget. The receiver stops waiting for 30 seconds, after which the user must explicitly start waiting again. Restarting the waiting session does not bypass that cooldown.
- If Keychain access is denied, the current connection can still be encrypted, but the UI says it was not remembered. Half-saved first-pairing records are removed when the other Mac does not acknowledge storage.

The short code is used with the existing **BoringSSL SPAKE2 password-authenticated key exchange**, not hashed directly into a TLS PSK. Mutual key confirmation gates all application data; independent AES-256-GCM keys and strict counters protect both directions. Every reconnect performs a fresh exchange using the stored strong credential. See [RFC 9257 §4.2](https://www.rfc-editor.org/rfc/rfc9257.html#section-4.2) for the distinction between low-entropy TLS PSKs and PAKE. This integration remains an experimental prototype without an independent security audit.

## Choose Mirror or Extend

Install **0.1.6 on both Macs**. On the host, choose the mode before starting:

| Mode | What the display Mac shows | Start button |
| --- | --- | --- |
| **Mirror** | The host's existing main screen, scaled to fit while keeping its aspect ratio | **Mirror display** |
| **Extend** | An independent desktop matched to the display Mac, with 1×/2× scaling | **Extend display** |

To change modes, disconnect, choose the other mode, and reconnect. The display Mac accepts either mode automatically.

Mirror uses ScreenCaptureKit to capture the existing main display. It does not create a virtual monitor. Extend uses the experimental virtual-display API described below.

## Display resolution (Extend)

Both Macs must run **0.1.6**; the sizing handshake uses protocol v3. Choose the resolution on the host before connecting:

| Setting | Desktop space | Text size on the receiver |
| --- | --- | --- |
| **Larger Text** | About 80% of the default logical dimensions | Larger |
| **Default (Recommended)** | Matches the receiver's full-screen logical viewport | Matches its macOS scaling |
| **More Space** | About 125% of the default logical dimensions | Smaller |

The receiver overlay shows the virtual desktop in points, its 1×/2× scale, the actual H.264 stream pixels and received FPS. Copy Diagnostics on either Mac for the receiver's screen/viewport dimensions and capture/encoder sizes. Disconnect and reconnect after changing the preset, the receiving screen or macOS display scaling. Exiting full screen keeps the negotiated resolution and fits it into the window.

This prototype accepts up to 5120 pixels on either stream axis and 16 megapixels in total. Actual codec support depends on the Mac; choose Larger Text if the requested size is rejected. This limit is explicit, with no hidden fallback to the old 1280 × 800 desktop.

## Then test the extended desktop

1. On the host, click **Disconnect**.
2. Click **Grant Screen Recording**. Allow MacPair in System Settings, then **quit and reopen the same app**. Screen Recording is only needed on the host.
3. Search again and select the display Mac. If the pairing was remembered, no code is needed. Otherwise enter its current six-digit code.
4. Choose **Extend**, then click **Extend display**.
5. An independent desktop matching the display Mac appears to the right of the host's desktop.
6. Drag a normal window past the host desktop's right edge. It should appear on the display Mac.
7. The display opens in full screen automatically. Double-click or press **Esc** to exit full screen.
8. Use **Arrange displays** on the host to change the display position.

Use the **host's** keyboard, mouse, and trackpad to operate the extended desktop. This version does not forward input from the display Mac or transmit audio.

To test Mirror instead, disconnect, select **Mirror**, and click **Mirror display**. Open or move a window on the host main screen and confirm the same action appears on the display Mac. No extra desktop should be added.

Disconnecting stops capture. In Extend mode, it also removes the virtual screen. macOS moves its windows back to the remaining displays. The display Mac can keep waiting for a new connection.

## Prove that no router is involved

Disconnect both Macs from their router/hotspot networks, but **leave the Wi-Fi radios on**. Unplug Ethernet/Thunderbolt network cables. Repeat both tests.

The host only connects to an `awdl*` interface discovered through Bonjour, and explicitly sets `NWParameters.requiredInterface` to it. A peer with no AWDL interface is not selectable. There is no silent LAN fallback.

The diagnostic panel shows Network.framework's interface report. Combine that with interface restriction and the disconnected-network test to verify the direct path.

Round-trip time is a network heartbeat measurement, not end-to-end display latency. The app targets up to 30 fps; actual speed and range must be measured on two Macs. A static desktop may show 0 new fps because ScreenCaptureKit emits no changed frames.

## Build and check

No network-fetched packages, cloud services, or paid developer account are needed. The build machine needs Xcode with Swift 6 and a macOS SDK. The published Swift Crypto/BoringSSL C source is vendored locally and built as a static library; the receiving Mac still needs only the App.

```bash
./scripts/build.sh             # universal arm64 + x86_64 app
./scripts/build.sh --native    # faster, current architecture only
./scripts/test.sh              # real local secure-pairing and H.264 checks
./scripts/test.sh --pairing    # remembered reconnect, Forget, expiry/lockout and scoped Keychain checks
./scripts/test.sh --display    # real 1×/2× displays + temporary fullscreen sizing check
./scripts/preview.sh           # render English/Chinese UI layout fixtures
./scripts/package.sh           # app + guides + complete source
```

Tests use generated image data and loopback networking. The optional Mirror check uses the App path printed by build.sh with `/Contents/MacOS/MacPair --mirror-smoke-test` appended. It reads one main-screen frame only if this app already has Screen Recording permission; otherwise it skips without requesting permission. It saves and sends no image. They do not automatically grant permissions or capture your existing desktop.

Build first, then grant Screen Recording and restart. Avoid rebuilding/re-signing the app during a permission test session. Bundle ID: `local.macpair.prototype`.

## How it works

```text
Host Mac                                      Display Mac
Virtual display → ScreenCaptureKit → H.264
                       ↓
                 SPAKE2 → AES-GCM / TCP ── AWDL ─────→ decode + window/full screen
                       ↑                          ↓
                       └──── heartbeat / RTT ─────┘
```

Extend-mode virtual-screen creation uses the **non-public CGVirtualDisplay API**. It works in the local test environment, but a macOS update may change compatibility. This is an experimental sideloaded app, not a promise of App Store availability.

Extend negotiates the receiver's logical screen size, backing pixels, scale and actual full-screen viewport before creating its virtual display. A Retina receiver gets a 2× HiDPI desktop and matching H.264 pixel dimensions. Default avoids an extra video resize when its measured viewport has even backing dimensions. Notched displays use the content area measured after full-screen entry. At 1×, odd dimensions round to the nearest even pixel for H.264. The viewer always preserves aspect ratio.

Mirror retains its aspect-preserving 1280 × 800 capture limit and creates no virtual display. Both modes target up to 30 fps. Extend's encoder bitrate scales with resolution (8–45 Mbps); this is a resolution-based budget, not a congestion controller. Audio, display-side input, multiple receivers and automatic reconnection are outside this prototype.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No display found | Start waiting on the display; keep both Wi-Fi radios on; allow Local Network; search again |
| Waiting for a direct interface | Move closer, confirm Wi-Fi and permissions, retry; the app will not fall back to the LAN |
| Pairing fails | Enter the current full code; starting a new waiting session changes it |
| Connection test passes, extension fails | Grant host Screen Recording, quit/reopen, then check Diagnostics |
| Frames arrive but no window is visible | Drag a normal window onto the new desktop; protected content may not be captured |
| Window will not move to the display | Use Arrange displays to check the screen position |
| Sleep interrupts the session | Wake both Macs and reconnect manually |
| You need help | Copy Diagnostics on both Macs; it includes system version, interface, errors, and frame counts, but no pairing code |

## Development workflow

Edit the source in this project, then use the build/check commands above. AirDrop archives and UI previews are saved to build/ and ignored by Git. In iCloud checkouts, generated Apps and compiler caches are kept in ~/Library/Caches/MacPair/<project-id>; build.sh prints the exact App path. This avoids Finder metadata from cloud synchronization invalidating the app signature. The shared scripts/project-paths.sh keeps build, test, preview, package and launch commands consistent.

```bash
git status
./scripts/build.sh --native
./scripts/test.sh
git diff
git add -A
git commit -m "Describe the change"
```

## Branding

Both supplied logos are in Resources/Branding/. MacPair_Icon.png is the application icon source; the build creates the macOS .icns resource automatically.

## Sources and license

- [Apple peer-to-peer networking](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)
- [Apple includePeerToPeer](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer)
- [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [OpenDisplay](https://github.com/peetzweg/opendisplay): source of the private virtual-display declarations.
- [OpenAirDisplay](https://github.com/nmt3325/openairdisplay): related AWDL work; not a runtime dependency.

GPL-3.0-only. See LICENSE and THIRD_PARTY_NOTICES.md. MacPair is an independent experiment and is not endorsed by those projects.
