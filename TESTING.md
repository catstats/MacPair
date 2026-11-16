# MacPair test guide

Version 0.1.1 adds a white highlight sweeping over the stationary gray searching label. The animation runs only while that label is visible and respects Reduce Motion. Search previews can be rendered with `./scripts/preview.sh --searching`; this UI update does not change the wireless protocol or video pipeline.

[中文测试指南](TESTING.zh-CN.md) · [Quick start](README.md)

## Version 0.1.7: compact connection UI

Check the English and Simplified Chinese interface at approximately 720 × 550:

- Choose Extend or Mirror and use the single **Connect** action. **Test connection** appears only after expanding Diagnostics.
- Open the gear button: Settings contains Language and Paired Macs → Forget.
- New peers have a visible **Pairing code** label. Saved peers skip the code.
- Normal display sessions enter full screen automatically; diagnostic tests do not open a video window.
- Disconnect: live RTT, path, FPS and frame count clear. Previous values appear only under **Last session**. Network and handshake errors remain available in the status detail and diagnostics.
- Synthetic preview fixtures use 7.6 ms / 455 frames only to reproduce the reported layout; these are not new measurements.

Local checks passed on 2026-11-17: both language layouts (host/display/disconnected/expanded diagnostics), universal build and strict signature, the disconnect-statistics regression, and the existing encrypted-pairing/codec/Keychain suite. Automatic full-screen entry uses the previously tested receiver path; it was not changed in this UI release.

The authentication protocol and Retina/video pipeline are unchanged from 0.1.6. Continue physical two-Mac acceptance below with 0.1.7 and the Connect / Diagnostics entry points.

## Version 0.1.6: six digits and remembered Macs

Both Macs must run **0.1.6**. Protocol v3 has a separate discovery service. Keep the earlier Retina/two-Mac acceptance below, using the new pairing flow:

1. Open Display Mac → Wait for connection. Confirm exactly six numeric digits, including leading zeroes if present.
2. On the host, enter the code and use Test connection. Confirm both apps report a remembered pairing. Disconnect.
3. Connect again with the host code field empty. Repeat after quitting/reopening both apps, and after exchanging host/display roles. A known Mac should need no code; the receiver still needs to be waiting.
4. Leave the invitation for five minutes. The code disappears; an already paired Mac should still connect. New Macs need New code.
5. Disconnect and choose Paired Macs → Forget on the receiver. The host's stale saved credential must fail. Forget its old entry too, then pair with a fresh code.
6. Try incorrect codes five times. The receiver stops advertising for 30 seconds and requires explicit waiting again. Do not include real codes or credentials in bug reports.
7. If Keychain permission is denied, confirm the connection is described as one-session-only and neither side presents an unconfirmed new credential as a remembered pair.

Local 0.1.6 checks passed on 2026-11-17, including universal arm64/x86_64 compilation and strict signature verification. The checks use actual SPAKE2 confirmation, authenticated encrypted TCP, 512 KB payloads, replay/tamper/plaintext rejection, wrong PINs, remembered reconnect without a PIN, same-name separation and revocation. The AppModel smoke check exercises both storage acknowledgements, one-time codes, Bonjour TXT identity discovery, restart with the same store, reconnect after code expiry, Forget, the global failure budget and half-save cleanup. A dedicated test service in the real login Keychain is written, read by a second MacPair process, and removed; the test never queries the user's pairing service.

These local checks do not replace a physical two-Mac AWDL test or an independent cryptographic security review. The user-reported different-Wi-Fi result below belongs to the earlier app. No new standalone/no-Wi-Fi success is claimed.

## Version 0.1.5: Retina resolution acceptance

Update **both Macs to 0.1.5**. Earlier versions cannot negotiate receiver geometry. On the host choose **Extend → Display resolution → Default (Recommended)** and connect. The receiver should enter full screen automatically.

1. Read the receiver overlay: desktop points × 1×/2× should equal stream pixels. On a 1280 × 832 pt Retina viewport, Default should report 2560 × 1664 px.
2. Compare a normal text window with the receiving Mac's own UI. Default should match its logical scaling, without stretched circles or clipped desktop edges.
3. Disconnect, choose **Larger Text**, reconnect: text grows and desktop space decreases. Repeat with **More Space**: text shrinks and desktop space increases. The aspect ratio stays consistent, apart from at most two points of even-pixel rounding.
4. Exit full screen, resize the viewer and re-enter full screen. The picture should fit without stretching; negotiated dimensions stay the same. Reconnect after changing macOS display scaling or the receiving screen.
5. Disconnect and confirm the virtual screen disappears. Repeat Mirror to ensure it still shows the existing main screen and adds no monitor. Mirror retains its 1280 × 800 capture bound.
6. If the result differs, use **Copy diagnostics on both Macs**. Record the model, macOS display scaling and which preset failed. Logs include screen/viewport points, backing pixels, virtual canvas, capture and encoder dimensions; the overlay reports parsed H.264 dimensions and FPS.

Local 0.1.5 checks on 2026-11-16:

- Receiver geometry validation, all three presets at 2×, odd 1× dimensions, portrait/ultrawide aspect ratios, notch viewport handling and size limits.
- Protocol v2 JSON roundtrip; altered encoded dimensions, invalid backing sizes and legacy v1 rejected.
- Actual H.264 encode/decode at 2560 × 1664, plus the existing 320 × 200 and 1230 × 800 checks. H.264 dimensions are checked against the negotiated session.
- Actual virtual displays at 1280 × 800 @1×, 1280 × 832 @2×, 1024 × 666 @2× and 1600 × 1040 @2×. CoreGraphics reported the expected logical AND pixel sizes after settling; every display was removed.
- Actual AppKit fullscreen measurement: 1920 × 1080 pt viewport, 3840 × 2160 backing pixels, 2×.
- English/Chinese component layouts; the viewer HUD preview uses synthetic dimensions and no live video.

Close existing MacPair display sessions before `./scripts/test.sh --display`. With the old session running, macOS rejected the additional display configuration (1014) and fullscreen entry; both checks passed after ending that session. The smoke check briefly creates displays and enters full screen. No existing desktop images are captured by these checks.

**The new 0.1.5 Retina path still needs the physical two-Mac acceptance above.** Prior user-reported success across different Wi-Fi networks belongs to the earlier version; it is not evidence that the new scaling path has already been tested on both Macs.

## Version 0.1.2: Mirror and Extend

Both peers must now run 0.1.6 (protocol v3). Choose **Extend** when following the original acceptance test below. After it passes, disconnect, choose **Mirror**, and click **Mirror display**. Confirm that moving/opening a window on the host main screen produces the same picture on the display Mac, and that no additional display is created. Disconnect and switch back to Extend to confirm its independent desktop still works.

Local checks now cover both mode handshakes, portrait/ultrawide/Retina aspect-ratio sizing, and actual H.264 decoding at the non-macroblock-aligned 1230 × 800 Mirror resolution. The optional real main-screen capture check was skipped in this environment because MacPair has no Screen Recording grant; it did not request permission or capture any image.

## Physical two-Mac acceptance test

Use the MacBook Pro as **Host Mac** and the MacBook Air as **Display Mac** (the roles can be reversed). Start with the English interface.

| Step | Action | Expected result |
| --- | --- | --- |
| 1 | Open the same MacPair version on both Macs | English UI; language menu also offers 简体中文 |
| 2 | Disconnect router/hotspot networks and wired network cables; leave Wi-Fi on | The app can only use its direct wireless path |
| 3 | Air: Display Mac → Wait for connection | A new six-digit numeric pairing code appears |
| 4 | Pro: Host Mac → Find nearby displays | Air appears with Direct AWDL available |
| 5 | Enter a deliberately incorrect six-digit code → Test connection | Pairing fails; no virtual display is created |
| 6 | Enter the correct current code → Test connection | AWDL connection test passed; RTT updates |
| 7 | Pro: Disconnect; grant Screen Recording; quit and reopen MacPair | The host has capture permission |
| 8 | Pro: search, pair again → Extend display | A separate desktop matching the receiver appears |
| 9 | Drag a TextEdit/Safari window past the host desktop's right edge | The window appears on Air while the host retains its own desktop |
| 10 | Observe automatic full screen; press Esc, then double-click | Full screen exits and re-enters; picture keeps its aspect ratio |
| 11 | Change language to 简体中文, then English | Controls and existing status/diagnostic messages update without disconnecting |
| 12 | Move/scroll a normal window for two minutes | New frames continue to arrive; record observed quality and RTT |
| 13 | Pro: Disconnect | Virtual screen disappears; its windows return to remaining screens |
| 14 | Connect again, then quit the display app or put a Mac to sleep | The host detects loss, stops capture, removes the virtual screen |
| 15 | Wake/reopen, start waiting again, pair again | A fresh session starts successfully |

If discovery fails, use **Copy diagnostics** on both Macs. Record the model and exact macOS version of each Mac, whether router networks were disconnected, and which step failed.

Do not turn the Wi-Fi radio off for the offline test: AWDL still needs the radio.

## User-reported result — 2026-11-16

The user first reported that the virtual display passed, then that the remaining checks passed. Their subsequent clarification narrows the verified connectivity result: **the Macs work when connected to different Wi-Fi networks; their “no Wi-Fi” scenario did not work.**

- Virtual extended display: passed, user report.
- Two-Mac display across different Wi-Fi networks: passed, user report.
- Standalone/no-access-point operation: not confirmed. The user did not specify whether “no Wi-Fi” meant turning off the Wi-Fi radio or leaving it enabled without joining a network.
- The user accepted this working version as sufficient. No further transport changes were requested.

The Wi-Fi radio must remain enabled for this wireless transport. Disabling it is a different test from disconnecting from a router or hotspot. Per-device models/OS versions, numeric latency, frame rate, and interface traces were not supplied.

## Verification record

Development environment: Apple Silicon MacBook Air, macOS 15.5 (24F74), Xcode's Swift 6.1.2 compiler, macOS 13 deployment target. Date: 2026-11-16.

The MacPair bilingual implementation passed these real local checks (including the new 0.1.2 mode and mirror-size checks):

- TCP framing with fragmented and combined packets, plus malformed-size/type rejection.
- Protocol version, Mirror/Extend mode and display-dimension validation; portrait, ultrawide and Retina mirror sizing.
- TLS-PSK roundtrip with a 512 KB payload and actual negotiated cipher verification.
- Wrong pairing code rejection (including the Network.framework TLS `waiting` state).
- Real VideoToolbox H.264 encoding and decoding; output dimensions and red-channel value checked.
- Real 1280 × 800 virtual display, separate from the primary desktop.
- Explicit removal verified against the system's online display list.
- Universal arm64/x86_64 compilation and local code-signature verification.

English/Chinese controls, nested status-message interpolation, switching back to English, and preference restoration also passed. The universal build is checked before packaging. Layout images are rendered from the app's own SwiftUI views; receiver fixtures use an example code and do not establish a wireless session. Desktop automation is unavailable in this workspace because its Documents parent is a symlink; component rendering is used for visual review.

Not yet validated:

- Standalone operation with both Wi-Fi radios on but neither Mac joined to a router or hotspot. The user-described “no Wi-Fi” attempt failed, with radio state unspecified.
- Real end-to-end display latency, wireless range, sustained throughput and sleep/reconnect behavior.
- A compatibility matrix identifying the runtime processor architecture and macOS version of each tested device.

Local tests cover individual components; the separate user report establishes the observed two-Mac result across different Wi-Fi networks. It does not establish standalone operation without an access point.
