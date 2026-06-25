#!/usr/bin/env bash
# Compatibility wrapper for reusable driving-POV capture review.
#   usage: bash tools/capture_drive.sh <out_subdir> [duration_s]
# Uses the sanctioned windowed viewport-PNG path from tools/drive_capture.gd.
set -euo pipefail
sub="${1:-after_capture}"
dur="${2:-16}"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out="tests/out/$sub"

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

echo "[1/2] warming import cache..."
"$godot_bin" --headless --import --path . >/dev/null 2>&1 || true

echo "[2/2] windowed viewport-PNG driving capture (${dur}s) -> ${out}/<timestamp>/"
defaults write org.godotengine.godot NSAppSleepDisabled -bool true || true
OUT_ROOT="$out" DURATION="$dur" GODOT_BIN="$godot_bin" bash tools/run_drive_capture.sh
