#!/usr/bin/env bash
# One-shot BEFORE-state footage of the CURRENT build at driving POV.
# Warm import (cold cache => blank scene), movie-capture a short drive, extract frames.
set -uo pipefail
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out="tests/out/before_capture"
rm -rf "$out"; mkdir -p "$out"

echo "[1/3] warming import cache..."
"$godot_bin" --headless --import --path . >/dev/null 2>&1 || true

echo "[2/3] movie-capturing driving pass..."
defaults write org.godotengine.godot NSAppSleepDisabled -bool true || true
caffeinate -dimsu "$godot_bin" --audio-driver Dummy --path . res://tools/perf_autodrive.tscn \
  --write-movie "$out/drive.avi" -- --duration=16 --steer-strength=0.18 >/dev/null 2>&1 || true

echo "[3/3] extracting frames..."
if [ -f "$out/drive.avi" ]; then
  ffmpeg -y -i "$out/drive.avi" -vf "fps=1" "$out/frame_%02d.png" >/dev/null 2>&1 || true
  ls -la "$out"/*.png 2>/dev/null | tail -20
  echo "DONE: $(ls "$out"/*.png 2>/dev/null | wc -l | tr -d ' ') frames"
else
  echo "FAIL: no movie written"
fi
