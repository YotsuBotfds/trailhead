#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

cd "$root"
exec "$godot_bin" --headless --fixed-fps 120 --path . res://tools/spikes/seam_crossing_golden_chain/seam_crossing_golden_chain.tscn -- "$@"
