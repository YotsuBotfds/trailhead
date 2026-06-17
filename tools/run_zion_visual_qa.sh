#!/usr/bin/env bash
set -euo pipefail

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_dir="${OUT_DIR:-tests/out/zion_visual_qa}"

# --audio-driver Dummy: this capture runs WITHOUT --headless (it needs a real render
# context to write PNGs), so force the silent audio driver or it blasts ambient SFX.
"$godot_bin" --audio-driver Dummy --path . res://tools/zion_windowed_visual_capture.tscn -- --out-dir="$out_dir"
