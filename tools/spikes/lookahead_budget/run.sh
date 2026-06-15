#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

cd "$root"
exec "$godot_bin" --headless --path . --script res://tools/spikes/lookahead_budget/lookahead_budget_spike.gd -- "$@"
