#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/project-paths.sh
app_binary="$task_app_path/Contents/MacOS/MacPair"
if [[ ! -x "$app_binary" ]]; then ./scripts/build.sh --native; fi
"$app_binary" --self-test
if [[ "${1:-}" == "--display" ]]; then
    "$app_binary" --display-smoke-test
    "$app_binary" --receiver-smoke-test
fi

if [[ "${1:-}" == "--pairing" || "${1:-}" == "--discovery" ]]; then
    "$app_binary" --pairing-smoke-test
    "$app_binary" --keychain-smoke-test
fi

if [[ "${1:-}" == "--discovery" ]]; then
    "$app_binary" --nearby-panel-smoke-test
fi

if [[ "${1:-}" == "--video" ]]; then
    "$app_binary" --video-pipeline-test
fi
