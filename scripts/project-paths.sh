#!/bin/bash
# Shared paths for build/test/preview/package scripts and the launcher.
# Keep app bundles outside iCloud: Finder metadata added during synchronization
# can invalidate the strict code-signature check on an otherwise identical app.
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ -n "${MACPAIR_BUILD_ROOT:-}" ]]; then
    task_build_root="$MACPAIR_BUILD_ROOT"
elif [[ "$task_root" == *"/Mobile Documents/com~apple~CloudDocs/"* ]]; then
    task_cache_id="$(printf '%s' "$task_root" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-12)"
    task_build_root="$HOME/Library/Caches/MacPair/$task_cache_id"
else
    task_build_root="$task_root/build"
fi
task_app_path="${MACPAIR_APP_PATH:-$task_build_root/MacPair.app}"
task_archive_root="$task_root/build"
