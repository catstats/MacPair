#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="${MACPAIR_APP_PATH:-$PWD/build/MacPair.app}"
if [[ ! -d "$app_path" ]]; then ./scripts/build.sh; fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
package="$PWD/build/package/MacPair"
mkdir -p "$package/Source"
ditto "$app_path" "$package/MacPair.app"
cp README.md "$package/README.txt"
cp README.zh-CN.md "$package/中文使用说明.txt"
cp LICENSE "$package/LICENSE"
for item in Sources Resources Tests scripts README.md README.zh-CN.md TESTING.md TESTING.zh-CN.md THIRD_PARTY_NOTICES.md LICENSE "Start MacPair.command"; do
    ditto "$item" "$package/Source/$item"
done
ditto -c -k --sequesterRsrc --keepParent "$package" "$PWD/build/MacPair-$version.zip"
echo "Package: $PWD/build/MacPair-$version.zip"
