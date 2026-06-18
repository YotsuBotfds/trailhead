#!/usr/bin/env bash
set -euo pipefail

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_root="${OUT_ROOT:-tests/out/perf}"
duration="${DURATION:-40}"
hitch_threshold_ms="${HITCH_THRESHOLD_MS:-20}"

# Runs windowed, not --headless, because this tool measures real rendered frames.
"$godot_bin" --audio-driver Dummy --path . res://tools/perf_autodrive.tscn -- \
  --out-root="$out_root" \
  --duration="$duration" \
  --hitch-threshold-ms="$hitch_threshold_ms"
