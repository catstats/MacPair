#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/project-paths.sh
stage="$task_build_root/staging/MacPair.app"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources" "$task_build_root/objects"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
architectures=(arm64 x86_64)
if [[ "${1:-}" == "--native" ]]; then architectures=("$(uname -m)"); fi
outputs=()
for arch in "${architectures[@]}"; do
    echo "Building $arch (macOS 13+)..."
    object="$task_build_root/objects/NativeBridge-$arch.o"
    binary="$task_build_root/objects/MacPair-$arch"
    xcrun clang -fobjc-arc -fmodules -isysroot "$sdk" -target "$arch-apple-macosx13.0" \
        -c Sources/NativeBridge.m -o "$object"
    xcrun swiftc -O -swift-version 5 -parse-as-library -sdk "$sdk" \
        -target "$arch-apple-macosx13.0" -module-cache-path "$task_build_root/ModuleCache" \
        -import-objc-header Sources/NativeBridge.h Sources/*.swift "$object" \
        -framework Cocoa -framework ScreenCaptureKit -framework VideoToolbox \
        -o "$binary"
    outputs+=("$binary")
done
if [[ "${#outputs[@]}" == 1 ]]; then
    cp "${outputs[0]}" "$stage/Contents/MacOS/MacPair"
else
    xcrun lipo -create "${outputs[@]}" -output "$stage/Contents/MacOS/MacPair"
fi
cp Resources/Info.plist "$stage/Contents/Info.plist"
cp LICENSE "$stage/Contents/Resources/LICENSE"
ditto Resources/zh-Hans.lproj "$stage/Contents/Resources/zh-Hans.lproj"
codesign --force --sign - --identifier local.macpair.prototype \
    --requirements '=designated => identifier "local.macpair.prototype"' "$stage"
codesign --verify --strict "$stage"
mkdir -p "$task_app_path"
ditto "$stage" "$task_app_path"
codesign --verify --strict "$task_app_path"
echo "Built: $task_app_path"
