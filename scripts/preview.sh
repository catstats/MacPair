#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/project-paths.sh
object="$task_build_root/objects/NativeBridge-$(uname -m).o"
if [[ ! -f "$object" ]]; then ./scripts/build.sh --native; fi
xcrun swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$task_build_root/ModuleCache" -import-objc-header Sources/NativeBridge.h \
    Sources/App.swift Sources/AppModel.swift Sources/Localization.swift Sources/PeerNetwork.swift Sources/Video.swift \
    Sources/VirtualScreen.swift Sources/Wire.swift Tests/Preview.swift \
    "$object" -o "$task_build_root/MacPairPreview"
"$task_build_root/MacPairPreview" "$task_archive_root/previews" "$@"
