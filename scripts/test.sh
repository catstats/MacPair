#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_binary="${MACPAIR_APP_PATH:-$PWD/build/MacPair.app}/Contents/MacOS/MacPair"
if [[ ! -x "$app_binary" ]]; then ./scripts/build.sh --native; fi
"$app_binary" --self-test
if [[ "${1:-}" == "--display" ]]; then
    "$app_binary" --display-smoke-test
fi
