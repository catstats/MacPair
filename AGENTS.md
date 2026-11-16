# MacPair development

MacPair is a native Swift macOS app. Its default UI language is English; Simplified Chinese is selectable in-app. Keep user-facing text in the existing localization system.

## Project map

- Sources/: SwiftUI app, peer discovery/TLS transport, screen capture, video codec, localization, and diagnostic entry points.
- Resources/: application identity and localized permission descriptions.
- Tests/: native component preview fixtures.
- scripts/: build, test, preview, and packaging commands.
- build/: generated App, archives, and caches, ignored by Git.

## Build and validate

Use ./scripts/build.sh for a universal arm64/x86_64 App; --native builds only this Mac's architecture. Run ./scripts/test.sh for local protocol, TLS, sizing, and real H.264 checks when those components change. The optional --display flag temporarily creates and removes a virtual screen. Preview UI changes with ./scripts/preview.sh; --searching and --mirror cover the added UI states. Package with ./scripts/package.sh.

Keep local.macpair.prototype stable for macOS permission continuity. Mirror captures the existing main display. Extend creates and later removes a CGVirtualDisplay. Preserve that distinction and cleanup behavior. The transport currently restricts connections to discovered AWDL interfaces.

## Verified scope

The user reported that the virtual display and use across two different Wi-Fi networks passed. Their described no-Wi-Fi case did not work; whether the radio was disabled or merely unassociated was not clarified. Do not label standalone no-access-point operation as verified. TESTING.md and TESTING.zh-CN.md contain the evidence and remaining checks.

Use codex/ prefixes for feature branches. Keep generated build output out of commits. This repository has no configured remote yet.
