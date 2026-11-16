#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/project-paths.sh
app_binary="$task_app_path/Contents/MacOS/MacPair"
if [[ ! -x "$app_binary" ]]; then ./scripts/build.sh --native; fi
"$app_binary" --self-test
if [[ "${1:-}" == "--display" ]]; then
    "$app_binary" --display-smoke-test
fi
