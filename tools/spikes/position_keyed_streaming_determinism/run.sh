#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
cd "$root"

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

exec "$godot_bin" --headless --fixed-fps 120 --path . --script res://tools/spikes/position_keyed_streaming_determinism/position_keyed_streaming_determinism.gd -- "$@"
