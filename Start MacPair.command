#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source scripts/project-paths.sh
if [[ ! -d "$task_app_path" ]]; then ./scripts/build.sh; fi
open "$task_app_path"
