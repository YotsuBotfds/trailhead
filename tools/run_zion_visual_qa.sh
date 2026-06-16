#!/usr/bin/env bash
set -euo pipefail

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_dir="${OUT_DIR:-tests/out/zion_visual_qa}"

"$godot_bin" --path . res://tools/zion_windowed_visual_capture.tscn -- --out-dir="$out_dir"
