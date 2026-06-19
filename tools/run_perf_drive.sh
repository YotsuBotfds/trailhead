#!/usr/bin/env bash
set -euo pipefail

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_root="${OUT_ROOT:-tests/out/perf}"
duration="${DURATION:-40}"
hitch_threshold_ms="${HITCH_THRESHOLD_MS:-20}"
steer_strength="${STEER_STRENGTH:-0.18}"

# macOS App Nap throttles CAMetalLayer present (nextDrawable) for backgrounded /
# napped windows up to ~1s, which corrupts the real-wall-clock dt this tool measures.
# Disable App Nap at the process level so the present path is never throttle-gated:
#   - NSAppSleepDisabled default on the Godot bundle id (org.godotengine.godot)
#   - caffeinate -dimsu wrapping the process so the system never idles it
# The harness (perf_autodrive.gd) additionally pulls the window foreground + on-top.
defaults write org.godotengine.godot NSAppSleepDisabled -bool true || true

# Runs windowed, not --headless, because this tool measures real rendered frames.
caffeinate -dimsu "$godot_bin" --audio-driver Dummy --path . res://tools/perf_autodrive.tscn -- \
  --out-root="$out_root" \
  --duration="$duration" \
  --hitch-threshold-ms="$hitch_threshold_ms" \
  --steer-strength="$steer_strength"
