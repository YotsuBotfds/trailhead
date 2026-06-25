#!/usr/bin/env bash
# One-shot BEFORE-state viewport-PNG capture of the CURRENT build at driving POV.
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

bash tools/capture_drive.sh before_capture "${DURATION:-16}"
