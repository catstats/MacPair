# MacPair development

MacPair is a native Swift macOS app. Its default UI language is English; Simplified Chinese is selectable in-app. Keep user-facing text in the existing localization system.

## Project map

- Sources/: SwiftUI app, peer discovery/authenticated encrypted transport, screen capture, video codec, localization, and diagnostic entry points.
- Resources/: application identity and localized permission descriptions.
- Tests/: native component preview fixtures.
- scripts/: build, test, preview, and packaging commands.
- Vendor/PasswordExchange/: locally vendored Apple Swift Crypto/BoringSSL C source, built statically for both architectures.
- build/: generated ZIP archives and preview images, ignored by Git.
- Website: https://catstats.github.io/MacPair/; website-source and gh-pages branches of this repository contain its source and compiled site. The local website/ checkout is separate from the app.
- iCloud checkouts keep generated app bundles/compiler caches under ~/Library/Caches/MacPair/<project-id> to preserve their signatures. scripts/project-paths.sh resolves all paths.

## Build and validate

Use ./scripts/build.sh for a universal arm64/x86_64 App; --native builds only this Mac's architecture. Run ./scripts/test.sh for local protocol, secure-pairing, sizing, and real H.264 checks when those components change. The optional --display flag temporarily creates and removes a virtual screen. Preview UI changes with ./scripts/preview.sh; --searching, --mirror and --viewer cover the added UI states. The --display tests briefly enter full screen and must run with existing MacPair display sessions disconnected. Package with ./scripts/package.sh. MACPAIR_BUILD_ROOT optionally overrides the generated-app/cache directory; MACPAIR_APP_PATH overrides the app path.

Keep local.macpair.prototype stable for macOS permission continuity. Mirror captures the existing main display. Extend creates and later removes a CGVirtualDisplay. Preserve that distinction and cleanup behavior. The transport currently restricts connections to discovered AWDL interfaces.

## Verified scope

The user reported that the virtual display and use across two different Wi-Fi networks passed. Their described no-Wi-Fi case did not work; whether the radio was disabled or merely unassociated was not clarified. Do not label standalone no-access-point operation as verified. TESTING.md and TESTING.zh-CN.md contain the evidence and remaining checks.

Use codex/ prefixes for feature branches. Keep generated build output out of commits. The public source repository is https://github.com/catstats/MacPair. Keep releases and source in sync.

Six-digit pairing uses SPAKE2, never a PIN-derived TLS PSK. Device identities are obtained with Bonjour TXT records and are bound into the authenticated exchange. Strong remembered-device secrets live only in the local login Keychain; no PINs or session keys go in preferences, logs or diagnostics. Preserve mutual credential-storage acknowledgements, expiry, the global failure budget, code-free reconnects and Forget revocation. `./scripts/test.sh --pairing` covers the receiver lifecycle plus a temporary, scoped cross-process Keychain probe. Keep the ad-hoc-compatible login-Keychain API; data-protection access groups require provisioning this prototype does not have.

Keep the default control window at about 720 × 550. Connect is the single main streaming action; Test connection stays inside Diagnostics. Language and remembered-Mac management live in the gear Settings popover. Archive successful-session statistics separately, clear live values at disconnect, and retain actionable failure details. Default video sessions must still enter full screen before measuring receiver geometry. Preview --disconnected and --diagnostics cover the added presentation states.

Discovery cards are app-owned nonactivating panels, never system pairing prompts. Only identified direct AWDL peers qualify, excluding self. Debounce availability; suppress repeated offers by stable device identity and respect dismissal, opt-out and explicit Stop. Restore the last role only on real app startup; tests/previews must not use real automation preferences or show unsolicited cards. Six-digit PAKE/Keychain authentication remains mandatory and screen sharing starts only after Connect. Discovery is not physical-distance measurement. Run --discovery and preview --nearby for these changes.

Low-latency video is optional within protocol v3: keep older peers on their existing 30 fps path, with no unsolicited new media packet types. New peers negotiate 60 fps and at most two frame credits across encoder/network/receiver submission. Replace only the latest RAW capture; never drop encoded predictive frames. Receiver parsing stays off MainActor; display-layer access stays on MainActor. GUI counters publish at most once per stats tick. ACK timings include the return leg and end at renderer submission, not physical presentation; never label them end-to-end display latency. Preserve real hardware query failures as unreported, and distinguish a required-hardware session from a reported hardware flag. --video checks generated encrypted Retina video with delayed ACKs; --performance-test benchmarks generated codec data and must not capture a desktop.
