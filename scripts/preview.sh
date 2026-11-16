#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f "build/objects/NativeBridge-$(uname -m).o" ]]; then ./scripts/build.sh --native; fi
xcrun swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$PWD/build/ModuleCache" -import-objc-header Sources/NativeBridge.h \
    Sources/App.swift Sources/AppModel.swift Sources/Localization.swift Sources/PeerNetwork.swift Sources/Video.swift \
    Sources/VirtualScreen.swift Sources/Wire.swift Tests/Preview.swift \
    "build/objects/NativeBridge-$(uname -m).o" -o build/MacPairPreview
build/MacPairPreview "$PWD/build/previews" "$@"
