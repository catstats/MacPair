#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -d build/MacPair.app ]]; then ./scripts/build.sh; fi
open "$PWD/build/MacPair.app"
