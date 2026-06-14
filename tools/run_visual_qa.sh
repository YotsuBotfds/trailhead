#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_dir="${VISUAL_QA_OUT_DIR:-tests/out/visual_qa}"

printf 'run: windowed visual capture -> %s\n' "$out_dir"
"$godot_bin" --path . res://tools/windowed_visual_capture.tscn -- --out-dir="$out_dir"

printf 'run: visual QA report\n'
python3 tools/build_visual_qa_report.py --capture-dir "$out_dir"
