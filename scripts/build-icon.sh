#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/project-paths.sh
original="$task_root/Resources/Branding/MacPair_Icon.png"
iconset="$task_build_root/MacPair.iconset"
output="${1:-$task_build_root/MacPair.icns}"
mkdir -p "$iconset" "$(dirname "$output")"
for points in 16 32 128 256 512; do
    /usr/bin/sips -z "$points" "$points" "$original" \
        --out "$iconset/icon_${points}x${points}.png" >/dev/null
    pixels=$((points * 2))
    if [[ "$pixels" == 1024 ]]; then
        cp "$original" "$iconset/icon_${points}x${points}@2x.png"
    else
        /usr/bin/sips -z "$pixels" "$pixels" "$original" \
            --out "$iconset/icon_${points}x${points}@2x.png" >/dev/null
    fi
done
/usr/bin/iconutil --convert icns --output "$output" "$iconset"
echo "Icon: $output"
