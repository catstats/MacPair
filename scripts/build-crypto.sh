#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/project-paths.sh"
arch="${1:-$(uname -m)}"
scratch="$task_build_root/crypto/$arch"
package="$task_root/Vendor/PasswordExchange"
mkdir -p "$scratch"
if ! xcrun swift build --package-path "$package" --scratch-path "$scratch" \
    --arch "$arch" --configuration release --product MacPairCrypto --quiet >"$scratch/build.log" 2>&1; then
    tail -80 "$scratch/build.log" >&2
    exit 1
fi
bin="$(xcrun swift build --package-path "$package" --scratch-path "$scratch" \
    --arch "$arch" --configuration release --show-bin-path)"
printf '%s\n' "$bin/libMacPairCrypto.a"
