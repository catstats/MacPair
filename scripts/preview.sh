#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/project-paths.sh
object="$task_build_root/objects/NativeBridge-$(uname -m).o"
if [[ ! -f "$object" ]]; then ./scripts/build.sh --native; fi
crypto_lib="$(./scripts/build-crypto.sh "$(uname -m)")"
xcrun swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$task_build_root/ModuleCache" -import-objc-header Sources/NativeBridge.h \
    Sources/App.swift Sources/AppModel.swift Sources/Localization.swift Sources/PeerNetwork.swift Sources/Video.swift Sources/VideoFlow.swift Sources/VideoReceiver.swift \
    Sources/VirtualScreen.swift Sources/Wire.swift Sources/Pairing.swift Sources/TrustedDevices.swift Sources/Discovery.swift Sources/NearbyDisplayCard.swift Tests/Preview.swift \
    "$object" "$crypto_lib" -lc++ -o "$task_build_root/MacPairPreview"
"$task_build_root/MacPairPreview" "$task_archive_root/previews" "$@"
