# MacPair test guide

Version 0.1.1 adds a white highlight sweeping over the stationary gray searching label. The animation runs only while that label is visible and respects Reduce Motion. Search previews can be rendered with `./scripts/preview.sh --searching`; this UI update does not change the wireless protocol or video pipeline.

[中文测试指南](TESTING.zh-CN.md) · [Quick start](README.md)

## Version 0.1.2: Mirror and Extend

Both peers must run 0.1.2 for Mirror support. Choose **Extend** when following the original acceptance test below. After it passes, disconnect, choose **Mirror**, and click **Mirror display**. Confirm that moving/opening a window on the host main screen produces the same picture on the display Mac, and that no additional display is created. Disconnect and switch back to Extend to confirm its independent desktop still works.

Local checks now cover both mode handshakes, portrait/ultrawide/Retina aspect-ratio sizing, and actual H.264 decoding at the non-macroblock-aligned 1230 × 800 Mirror resolution. The optional real main-screen capture check was skipped in this environment because MacPair has no Screen Recording grant; it did not request permission or capture any image.

## Physical two-Mac acceptance test

Use the MacBook Pro as **Host Mac** and the MacBook Air as **Display Mac** (the roles can be reversed). Start with the English interface.

| Step | Action | Expected result |
| --- | --- | --- |
| 1 | Open the same MacPair version on both Macs | English UI; language menu also offers 简体中文 |
| 2 | Disconnect router/hotspot networks and wired network cables; leave Wi-Fi on | The app can only use its direct wireless path |
| 3 | Air: Display Mac → Wait for connection | A new 12-character pairing code appears |
| 4 | Pro: Host Mac → Find nearby displays | Air appears with Direct AWDL available |
| 5 | Enter a deliberately incorrect 12-character code → Test connection | Pairing fails; no virtual display is created |
| 6 | Enter the correct current code → Test connection | AWDL connection test passed; RTT updates |
| 7 | Pro: Disconnect; grant Screen Recording; quit and reopen MacPair | The host has capture permission |
| 8 | Pro: search, pair again → Extend display | A separate 1280 × 800 desktop appears |
| 9 | Drag a TextEdit/Safari window past the host desktop's right edge | The window appears on Air while the host retains its own desktop |
| 10 | Double-click the display video, then Esc | Full screen enters and exits |
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
