#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/project-paths.sh
if [[ ! -d "$task_app_path" ]]; then ./scripts/build.sh; fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app_path/Contents/Info.plist")"
package="$task_build_root/package/MacPair"
mkdir -p "$package/Source" "$task_archive_root"
ditto "$task_app_path" "$package/MacPair.app"
codesign --verify --strict "$package/MacPair.app"
cp README.md "$package/README.txt"
cp README.zh-CN.md "$package/中文使用说明.txt"
cp LICENSE "$package/LICENSE"
for item in Sources Resources Tests scripts README.md README.zh-CN.md TESTING.md TESTING.zh-CN.md THIRD_PARTY_NOTICES.md LICENSE AGENTS.md "Start MacPair.command"; do
    ditto "$item" "$package/Source/$item"
done
archive="$task_archive_root/MacPair-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$package" "$archive"
echo "Package: $archive"
